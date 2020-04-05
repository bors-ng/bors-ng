defmodule BorsNG.GitHub.OAuth2 do
  @moduledoc """
  An OAuth2 strategy for GitHub.
  """
  use OAuth2.Strategy

  alias OAuth2.Strategy.AuthCode

  defp config do
    github = Confex.fetch_env!(:bors, :html_github_root)

    cfg = [
      site: Confex.fetch_env!(:bors, :api_github_root),
      strategy: BorsNG.GitHub.OAuth2,
      authorize_url: "#{github}/login/oauth/authorize",
      token_url: "#{github}/login/oauth/access_token"
    ]

    :bors
    |> Confex.fetch_env!(BorsNG.GitHub.OAuth2)
    |> Keyword.merge(cfg)
  end

  # Public API

  @type t :: OAuth2.Client.t()

  def client do
    OAuth2.Client.new(config())
    |> OAuth2.Client.put_serializer("application/json", Poison)
  end

  @spec authorize_url!() :: binary
  def authorize_url! do
    OAuth2.Client.authorize_url!(client(), [])
  end

  @spec get_token!(keyword) :: t
  def get_token!(params \\ []) do
    params = Keyword.merge(params, client_secret: client().client_secret)
    OAuth2.Client.get_token!(client(), params)
  end

  @doc """
  Get info about the user we are now logged in as
  """
  @spec get_user!(t) :: BorsNG.GitHub.User.t()
  def get_user!(client) do
    client
    |> OAuth2.Client.get!("/user")
    |> Map.fetch!(:body)
    |> BorsNG.GitHub.User.from_json!()
  end

  # Strategy Callbacks

  def authorize_url(client, params) do
    AuthCode.authorize_url(client, params)
  end

  def get_token(client, params, headers) do
    client
    |> put_param(:client_secret, client.client_secret)
    |> put_header("Accept", "application/json")
    |> AuthCode.get_token(params, headers)
  end
end
