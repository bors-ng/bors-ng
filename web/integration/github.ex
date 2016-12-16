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

  def get_my_repos!(installation_xref) do
    cfg = config()
    token = get_installation_token!(installation_xref)
    true = is_binary(token)
    %{body: raw, status_code: 200} = HTTPoison.get!(
      "#{cfg[:site]}/installation/repositories",
      [{"Authorization", "token #{token}"}, {"Accept", @content_type}])
    Poison.decode!(raw)
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
end
