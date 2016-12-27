defmodule Aelita2.Integration.GitHub do
  @moduledoc """
  Wrappers for accessing the GitHub Integration API.
  """

  @content_type "application/vnd.github.machine-man-preview+json"

  # Get a repository by ID:
  # https://api.github.com/repositories/59789129

  # Public API

  def config do
    Application.get_env(:aelita2, Aelita2.Integration.GitHub)
    |> Keyword.merge([site: "https://api.github.com"])
  end

  def get_installation_token!(installation_xref) do
    import Joken
    cfg = config()
    pem = JOSE.JWK.from_pem(cfg[:pem])
    jwt_token = %{iat: current_time, exp: current_time + 400, iss: cfg[:iss]}
    |> token()
    |> sign(rs256(pem))
    |> get_compact()
    %{body: raw, status_code: 201} = HTTPoison.post!(
      "#{cfg[:site]}/installations/#{installation_xref}/access_tokens",
      "",
      [{"Authorization", "Bearer #{jwt_token}"}, {"Accept", @content_type}])
    Poison.decode!(raw)["token"]
  end

  def get_my_repos!(token) when is_binary(token) do
    cfg = config()
    %{body: raw, status_code: 200} = HTTPoison.get!(
      "#{cfg[:site]}/installation/repositories",
      [{"Authorization", "token #{token}"}, {"Accept", @content_type}])
    Poison.decode!(raw)["repositories"]
    |> Enum.map(&%{
      id: &1["id"],
      name: &1["full_name"],
      permissions: %{
        admin: &1["permissions"]["admin"],
        push: &1["permissions"]["push"],
        pull: &1["permissions"]["pull"]
      },
      owner: %{
        id: &1["owner"]["id"],
        login: &1["owner"]["login"],
        avatar_url: &1["owner"]["avatar_url"],
        type: &1["owner"]["type"]}})
  end

  def copy_branch!(token, repository_id, from, to) when is_binary(token) do
    cfg = config()
    %{body: raw, status_code: 200} = HTTPoison.get!(
      "#{cfg[:site]}/repositories/#{repository_id}/branches/#{from}",
      [{"Authorization", "token #{token}"}, {"Accept", @content_type}])
    sha = Poison.decode!(raw)["commit"]["sha"]
    force_push!(token, repository_id, sha, to)
  end

  def merge_branch!(token, repository_id, from, to, commit_message) when is_binary(token) do
    cfg = config()
    %{body: raw, status_code: 200} = HTTPoison.patch!(
      "#{cfg[:site]}/repositories/#{repository_id}/merges",
      Poison.encode!(%{
        "base": to,
        "head": from,
        "commit_message": commit_message
        }),
      [{"Authorization", "token #{token}"}, {"Accept", @content_type}])
    data = Poison.decode!(raw)
    %{
      commit: data["sha"],
      tree: data["tree"]["sha"]
    }
  end

  def synthesize_commit!(token, repository_id, branch, tree, parents, commit_message) when is_binary(token) do
    cfg = config()
    %{body: raw, status_code: 200} = HTTPoison.post!(
      "#{cfg[:site]}/repositories/#{repository_id}/git/commits",
      Poison.encode!(%{
        "parents": parents,
        "tree": tree,
        "message": commit_message
        }),
      [{"Authorization", "token #{token}"}, {"Accept", @content_type}])
    sha = Poison.decode!(raw)["sha"]
    force_push!(token, repository_id, sha, branch)
  end

  def force_push!(token, repository_id, sha, to) do
    cfg = config()
    %{body: raw, status_code: status_code} = HTTPoison.get!(
      "#{cfg[:site]}/repositories/#{repository_id}/branches/#{to}",
      [{"Authorization", "token #{token}"}, {"Accept", @content_type}])
    %{body: _, status_code: 200} = cond do
      status_code == 404 ->
        HTTPoison.post!(
          "#{cfg[:site]}/repositories/#{repository_id}/refs",
          Poison.encode!(%{
            "ref": "refs/heads/#{to}",
            "sha": sha
            }),
          [{"Authorization", "token #{token}"}, {"Accept", @content_type}])
      sha != Poison.decode!(raw)["commit"]["sha"] ->
        HTTPoison.patch!(
          "#{cfg[:site]}/repositories/#{repository_id}/refs/heads/#{to}",
          Poison.encode!(%{
            "force": true,
            "sha": sha
            }),
          [{"Authorization", "token #{token}"}, {"Accept", @content_type}])
      true -> %{body: "", status_code: 200}
    end
    sha
  end

  def get_commit_status!(token, repository_id, sha) do
    cfg = config()
    %{body: raw, status_code: 200} = HTTPoison.get!(
      "#{cfg[:site]}/repositories/#{repository_id}/commits/#{sha}/status",
      [{"Authorization", "token #{token}"}, {"Accept", @content_type}])
    Poison.decode!(raw)["statuses"]
    |> Enum.map(&{&1["context"], map_state_to_status(&1["state"])})
    |> Map.new()
  end

  def map_state_to_status(state) do
    case state do
      "pending" -> :waiting
      "success" -> :ok
      "failure" -> :err
      "error" -> :err
    end
  end
end
