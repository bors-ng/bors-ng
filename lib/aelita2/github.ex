defmodule Aelita2.GitHub do

  alias Aelita2.GitHub.RepoConnection

  @moduledoc """
  Wrappers around the GitHub REST API.
  """

  @content_type_raw "application/vnd.github.VERSION.raw"

  defp config do
    cfg = [
      site: "https://api.github.com",
      require_visibility: :public
    ]
    :aelita2
    |> Application.get_env(Aelita2.GitHub)
    |> Keyword.merge(cfg)
  end

  def get_repo!(token, id) do
    resp = HTTPoison.get!(
      "#{config()[:site]}/repositories/#{id}",
      [{"Authorization", "token #{token}"}])
    case resp do
      %{body: raw, status_code: 200} -> (
        r = Poison.decode!(raw)
        {:ok, %{
          id: r["id"],
          name: r["full_name"],
          permissions: %{
            admin: r["permissions"]["admin"],
            push: r["permissions"]["push"],
            pull: r["permissions"]["pull"]
          },
          owner: %{
            id: r["owner"]["id"],
            login: r["owner"]["login"],
            avatar_url: r["owner"]["avatar_url"],
            type: r["owner"]["type"]}}}
      )
      %{status_code: code} -> {:err, code}
    end
  end

  def push!(repo_conn, sha, to) do
    %{body: _, status_code: 200} = patch!(
      repo_conn,
      "git/refs/heads/#{to}",
      Poison.encode!(%{
        "sha": sha
        }))
    sha
  end

  def copy_branch!(repo_conn, from, to) do
    %{body: raw, status_code: 200} = get!(repo_conn, "branches/#{from}")
    sha = Poison.decode!(raw)["commit"]["sha"]
    force_push!(repo_conn, sha, to)
  end

  def merge_branch!(repo_conn, %{
    from: from,
    to: to,
    commit_message: commit_message}) do
    %{body: raw, status_code: status_code} = post!(
      repo_conn,
      "merges",
      Poison.encode!(%{
        "base": to,
        "head": from,
        "commit_message": commit_message
        }))
    case status_code do
      201 ->
        data = Poison.decode!(raw)
        %{
          commit: data["sha"],
          tree: data["commit"]["tree"]["sha"]
        }
      409 ->
        :conflict
    end
  end

  def synthesize_commit!(repo_conn, %{
    branch: branch,
    tree: tree,
    parents: parents,
    commit_message: commit_message}) do
    %{body: raw, status_code: 201} = post!(
      repo_conn,
      "git/commits",
      Poison.encode!(%{
        "parents": parents,
        "tree": tree,
        "message": commit_message
        }))
    sha = Poison.decode!(raw)["sha"]
    force_push!(repo_conn, sha, branch)
  end

  def force_push!(repo_conn, sha, to) do
    %{body: raw, status_code: status_code} = get!(repo_conn, "branches/#{to}")
    %{body: _, status_code: 200} = cond do
      status_code == 404 ->
        post!(
          repo_conn,
          "git/refs",
          Poison.encode!(%{
            "ref": "refs/heads/#{to}",
            "sha": sha
            }))
      sha != Poison.decode!(raw)["commit"]["sha"] ->
        patch!(
          repo_conn,
          "git/refs/heads/#{to}",
          Poison.encode!(%{
            "force": true,
            "sha": sha
            }))
      true -> %{body: "", status_code: 200}
    end
    sha
  end

  def get_commit_status!(repo_conn, sha) do
    %{body: raw, status_code: 200} = get!(repo_conn, "commits/#{sha}/status")
    Poison.decode!(raw)["statuses"]
    |> Enum.map(&{&1["context"], map_state_to_status(&1["state"])})
    |> Map.new()
  end

  def get_file(repo_conn, branch, path) do
    %{body: raw, status_code: status_code} = get!(
      repo_conn,
      "contents/#{path}",
      [{"Accept", @content_type_raw}],
      [params: [ref: branch]])
    case status_code do
      404 -> nil
      200 -> raw
    end
  end

  def post_comment!(repo_conn, number, body) do
    %{status_code: 201} = post!(
      repo_conn,
      "issues/#{number}/comments",
      Poison.encode!(%{body: body}))
  end

  def get_user_by_login(token, login) when is_binary(token) do
    resp = HTTPoison.get!(
      "#{config()[:site]}/users/#{login}",
      [{"Authorization", "token #{token}"}])
    case resp do
      %{body: raw, status_code: 200} ->
        r = Poison.decode!(raw)
        {:ok, %{
          id: r["id"],
        }}
      %{status_code: 404} ->
        {:error, :not_found}
    end
  end

  defp post!(
    %RepoConnection{token: token, repo: repo},
    path,
    body,
    headers \\ []) do
    HTTPoison.post!(
      "#{config()[:site]}/repositories/#{repo}/#{path}",
      body,
      [{"Authorization", "token #{token}"}] ++ headers)
  end

  defp patch!(
    %RepoConnection{token: token, repo: repo},
    path,
    body,
    headers \\ []) do
    HTTPoison.patch!(
      "#{config()[:site]}/repositories/#{repo}/#{path}",
      body,
      [{"Authorization", "token #{token}"}] ++ headers)
  end

  defp get!(
    %RepoConnection{token: token, repo: repo},
    path,
    headers \\ [],
    params \\ []) do
    HTTPoison.get!(
      "#{config()[:site]}/repositories/#{repo}/#{path}",
      [{"Authorization", "token #{token}"}] ++ headers,
      params)
  end

  def map_state_to_status(state) do
    case state do
      "pending" -> :running
      "success" -> :ok
      "failure" -> :err
      "error" -> :err
    end
  end
end
