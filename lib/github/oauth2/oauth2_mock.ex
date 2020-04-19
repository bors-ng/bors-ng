defmodule BorsNG.GitHub.OAuth2Mock do
  @moduledoc """
  This is only used for development and testing.
  """

  @code "MOCK_GITHUB_AUTHORIZE_CODE"
  @url "MOCK_GITHUB_AUTHORIZE_URL"
  @token "MOCK_GITHUB_AUTHORIZE_TOKEN"
  @avatar "https://cdn.rawgit.com/notriddle/bors-ng/b9e756/icon/bors-eye.svg"

  @type t :: map
  @type tuser :: BorsNG.GitHub.User.t()

  @spec authorize_url!() :: binary
  def authorize_url! do
    "/auth/github/callback?code=#{@code}\##{@url}"
  end

  @spec get_token!(keyword) :: t
  def get_token!(args) do
    code = args[:code]
    if code != @code, do: raise("Incorrect GitHub auth code: #{code}")
    %{token: %{access_token: @token}}
  end

  @spec get_user!(t) :: tuser
  def get_user!(client) do
    token = client.token.access_token
    if token != @token, do: raise("Incorrect GitHub auth code: #{token}")
    %BorsNG.GitHub.User{id: 23, login: "space", avatar_url: @avatar}
  end
end
