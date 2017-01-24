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
    :aelita2
    |> Application.get_env(Aelita2.GitHub)
    |> Keyword.merge(Application.get_env(:aelita2, Aelita2.GitHub.OAuth2))
    |> Keyword.merge(cfg)
  end

  defp params do
    [scope: config()[:scope]]
  end

  # Public API

  @type t :: OAuth2.Client.t

  def client do
    OAuth2.Client.new(config())
  end

  @spec authorize_url!() :: binary
  def authorize_url! do
    OAuth2.Client.authorize_url!(client(), params())
  end

  @spec get_token!(keyword) :: t
  def get_token!(params \\ []) do
    params = Keyword.merge(params, client_secret: client().client_secret)
    OAuth2.Client.get_token!(client(), params)
  end

  @doc """
  Get info about the user we are now logged in as
  """
  @spec get_user!(t) :: map
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
