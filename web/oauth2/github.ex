defmodule Aelita2.OAuth2.GitHub do
  @moduledoc """
  An OAuth2 strategy for GitHub.
  """
  use OAuth2.Strategy

  alias OAuth2.Strategy.AuthCode

  def config do
    cfg = [
      strategy: Aelita2.OAuth2.GitHub,
      site: "https://api.github.com",
      authorize_url: "https://github.com/login/oauth/authorize",
      token_url: "https://github.com/login/oauth/access_token"]
    Application.get_env(:aelita2, Aelita2.OAuth2.GitHub)
    |> Keyword.merge(cfg)
  end

  # Public API

  def client do
    config()
    |> OAuth2.Client.new()
  end

  def authorize_url!(params \\ []) do
    OAuth2.Client.authorize_url!(client(), params)
  end

  def get_token!(params \\ [], _headers \\ []) do
    OAuth2.Client.get_token!(client(), Keyword.merge(params, client_secret: client().client_secret))
  end

  @doc """
  List repoes that the oAuth-authenticated user is a contributor to.
  """
  def get_my_repos!(github_access_token) when is_binary(github_access_token) do
    visibility = case config()[:require_visibility] do
      :public -> "public"
      :all -> "all"
    end
    %{body: raw, status_code: 200} = HTTPoison.get!(
      "#{config()[:site]}/user/repos",
      [{"Authorization", "token #{github_access_token}"}],
      [params: [{"visibility", visibility}, {"sort", "full_name"}]])
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
