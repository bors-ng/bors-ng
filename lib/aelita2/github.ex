defmodule Aelita2.GitHub do

  @content_type_raw "application/vnd.github.VERSION.raw"

  @moduledoc """
  Wrappers around the GitHub REST API.
  """

  defp config do
    cfg = [
      site: "https://api.github.com",
      require_visibility: :public
    ]
    Application.get_env(:aelita2, Aelita2.GitHub)
    |> Keyword.merge(cfg)
  end

  def get_repo!(token, id) when is_binary(token) do
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

  def copy_branch!(token, repository_id, from, to) when is_binary(token) do
    cfg = config()
    %{body: raw, status_code: 200} = HTTPoison.get!(
      "#{cfg[:site]}/repositories/#{repository_id}/branches/#{from}",
      [{"Authorization", "token #{token}"}])
    sha = Poison.decode!(raw)["commit"]["sha"]
    force_push!(token, repository_id, sha, to)
  end

  def merge_branch!(token, repository_id, from, to, commit_message) when is_binary(token) do
    cfg = config()
    %{body: raw, status_code: status_code} = HTTPoison.post!(
      "#{cfg[:site]}/repositories/#{repository_id}/merges",
      Poison.encode!(%{
        "base": to,
        "head": from,
        "commit_message": commit_message
        }),
      [{"Authorization", "token #{token}"}])
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

  def synthesize_commit!(token, repository_id, branch, tree, parents, commit_message) when is_binary(token) do
    cfg = config()
    %{body: raw, status_code: 201} = HTTPoison.post!(
      "#{cfg[:site]}/repositories/#{repository_id}/git/commits",
      Poison.encode!(%{
        "parents": parents,
        "tree": tree,
        "message": commit_message
        }),
      [{"Authorization", "token #{token}"}])
    sha = Poison.decode!(raw)["sha"]
    force_push!(token, repository_id, sha, branch)
  end

  def force_push!(token, repository_id, sha, to) do
    cfg = config()
    %{body: raw, status_code: status_code} = HTTPoison.get!(
      "#{cfg[:site]}/repositories/#{repository_id}/branches/#{to}",
      [{"Authorization", "token #{token}"}])
    %{body: _, status_code: 200} = cond do
      status_code == 404 ->
        HTTPoison.post!(
          "#{cfg[:site]}/repositories/#{repository_id}/git/refs",
          Poison.encode!(%{
            "ref": "refs/heads/#{to}",
            "sha": sha
            }),
          [{"Authorization", "token #{token}"}])
      sha != Poison.decode!(raw)["commit"]["sha"] ->
        HTTPoison.patch!(
          "#{cfg[:site]}/repositories/#{repository_id}/git/refs/heads/#{to}",
          Poison.encode!(%{
            "force": true,
            "sha": sha
            }),
          [{"Authorization", "token #{token}"}])
      true -> %{body: "", status_code: 200}
    end
    sha
  end

  def get_commit_status!(token, repository_id, sha) do
    cfg = config()
    %{body: raw, status_code: 200} = HTTPoison.get!(
      "#{cfg[:site]}/repositories/#{repository_id}/commits/#{sha}/status",
      [{"Authorization", "token #{token}"}])
    Poison.decode!(raw)["statuses"]
    |> Enum.map(&{&1["context"], map_state_to_status(&1["state"])})
    |> Map.new()
  end

  def get_file(token, repository_id, branch, path) do
    cfg = config()
    %{body: raw, status_code: status_code} = HTTPoison.get!(
      "#{cfg[:site]}/repositories/#{repository_id}/contents/#{path}",
      [{"Authorization", "token #{token}"}, {"Accept", @content_type_raw}],
      [params: [ref: branch]])
    case status_code do
      404 -> nil
      200 -> raw
    end
  end

  def post_comment!(token, repository_id, number, body) do
    cfg = config()
    %{status_code: 201} = HTTPoison.post!(
      "#{cfg[:site]}/repositories/#{repository_id}/issues/#{number}/comments",
      Poison.encode!(%{body: body}),
      [{"Authorization", "token #{token}"}])
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

  def map_state_to_status(state) do
    case state do
      "pending" -> :running
      "success" -> :ok
      "failure" -> :err
      "error" -> :err
    end
  end
end
