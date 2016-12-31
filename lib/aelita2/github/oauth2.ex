defmodule Aelita2.GitHub.OAuth2 do
  @moduledoc """
  An OAuth2 strategy for GitHub.
  """
  use OAuth2.Strategy

  alias OAuth2.Strategy.AuthCode

  defp config do
    cfg = [
      strategy: Aelita2.GitHub.OAuth2,
      site: "https://api.github.com",
      authorize_url: "https://github.com/login/oauth/authorize",
      token_url: "https://github.com/login/oauth/access_token"
    ]
    Application.get_env(:aelita2, Aelita2.GitHub)
    |> Keyword.merge(Application.get_env(:aelita2, Aelita2.GitHub.OAuth2))
    |> Keyword.merge(cfg)
  end

  defp params do
    [scope: config()[:scope]]
  end

  # Public API

  def client do
    OAuth2.Client.new(config())
  end

  def authorize_url!() do
    OAuth2.Client.authorize_url!(client(), params)
  end

  def get_token!(params \\ [], _headers \\ []) do
    OAuth2.Client.get_token!(client(), Keyword.merge(params, client_secret: client().client_secret))
  end

  @doc """
  List repoes that the oAuth-authenticated user is a contributor to.
  """
  def get_my_repos!(github_access_token, url \\ nil) when is_binary(github_access_token) do
    visibility = case config()[:require_visibility] do
      :public -> "public"
      :all -> "all"
    end
    {url, params} = case url do
      nil -> {"#{config()[:site]}/user/repos", [params: [{"visibility", visibility}, {"sort", "full_name"}]]}
      url -> {url, URI.parse(url).query |> URI.query_decoder() |> Enum.to_list()}
    end
    %{body: raw, status_code: 200, headers: headers} = HTTPoison.get!(
      url,
      [{"Authorization", "token #{github_access_token}"}],
      params)
    response = Poison.decode!(raw)
    |> Enum.map(&%{
      id: &1["id"],
      name: &1["full_name"],
      html_url: &1["html_url"],
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
    next_headers = Enum.filter(headers, fn h -> {n, _} = h; n == "Link" end)
    |> Enum.map(fn h -> {_, v} = h; ExLinkHeader.parse!(v) end)
    |> Enum.filter(&!is_nil(&1.next))
    next = case next_headers do
      [] -> nil
      [next] -> next.next.url
    end
    {response, next}
  end

  @doc """
  Get info about the user we are now logged in as
  """
  def get_user!(client) do
    OAuth2.Client.get! client, "/user"
  end

  # Strategy Callbacks

  def authorize_url(client, params) do
    AuthCode.authorize_url(client, params)
  end

  def get_token(client, params, headers) do
    client
    |> put_header("Accept", "application/json")
    |> AuthCode.get_token(params, headers)
  end
end
