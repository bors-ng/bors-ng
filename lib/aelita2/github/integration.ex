defmodule Aelita2.GitHub.Integration do
  @moduledoc """
  Wrappers for accessing the GitHub Integration API.
  """

  @content_type "application/vnd.github.machine-man-preview+json"

  # Get a repository by ID:
  # https://api.github.com/repositories/59789129

  # Public API

  @spec config() :: keyword
  defp config do
    :aelita2
    |> Application.get_env(Aelita2.GitHub.Integration)
    |> Keyword.merge(Application.get_env(:aelita2, Aelita2.GitHub))
    |> Keyword.merge([site: "https://api.github.com"])
  end

  @spec get_installation_token!(number) :: binary
  def get_installation_token!(installation_xref) do
    import Joken
    cfg = config()
    pem = JOSE.JWK.from_pem(cfg[:pem])
    jwt_token = %{
      iat: current_time(),
      exp: current_time() + 400,
      iss: cfg[:iss]}
    |> token()
    |> sign(rs256(pem))
    |> get_compact()
    %{body: raw, status_code: 201} = HTTPoison.post!(
      "#{cfg[:site]}/installations/#{installation_xref}/access_tokens",
      "",
      [{"Authorization", "Bearer #{jwt_token}"}, {"Accept", @content_type}])
    Poison.decode!(raw)["token"]
  end

  @spec get_my_repos!(binary) :: [map]
  def get_my_repos!(token) do
    get_my_repos_!(token, "#{config()[:site]}/installation/repositories", [])
  end

  @spec get_my_repos_!(binary, binary, [map]) :: [map]
  defp get_my_repos_!(token, url, append) when is_binary(token) do
    params = URI.parse(url).query |> URI.query_decoder() |> Enum.to_list()
    %{body: raw, status_code: 200, headers: headers} = HTTPoison.get!(
      url,
      [{"Authorization", "token #{token}"}, {"Accept", @content_type}],
      [params: params])
    repositories = Poison.decode!(raw)["repositories"]
    |> Enum.map(&%{
      id: &1["id"],
      name: &1["full_name"],
      owner: %{
        id: &1["owner"]["id"],
        login: &1["owner"]["login"],
        avatar_url: &1["owner"]["avatar_url"],
        type: &1["owner"]["type"]}})
    |> Enum.concat(append)
    next_headers = headers
    |> Enum.filter(&(elem(&1, 0) == "Link"))
    |> Enum.map(&(ExLinkHeader.parse!(elem(&1, 1))))
    |> Enum.filter(&!is_nil(&1.next))
    case next_headers do
      [] -> repositories
      [next] -> get_my_repos_!(token, next.next.url, repositories)
    end
  end
end
