defmodule Aelita2.GitHubMock do
  @moduledoc """
  This is only used for development and testing.
  """

  def push!(_, _, _) do
    raise("unimplemented")
  end
  def copy_branch!(_, _, _) do
    raise("unimplemented")
  end
  def merge_branch!(_, _) do
    raise("unimplemented")
  end
  def synthesize_commit!(_, _) do
    raise("unimplemented")
  end
  def get_file(_, _, _) do
    raise("unimplemented")
  end
  def post_comment!(_, _, _) do
    raise("unimplemented")
  end
  def get_commit_status!(_, _) do
    raise("unimplemented")
  end
  def get_repo!(_, _) do
    raise("unimplemented")
  end
  def get_user_by_login(_, login) do
    case login do
      "ghost" ->
        {:ok, %{id: 13}}
      _ ->
        {:error, :not_found}
    end
  end
  defdelegate map_state_to_status(state), to: Aelita2.GitHub
end
defmodule Aelita2.GitHubMock.RepoConnection do
  @moduledoc """
  This is only used for development and testing.
  """

  defdelegate connect!(repo_conn), to: Aelita2.GitHub.RepoConnection
end
defmodule Aelita2.GitHubMock.OAuth2 do
  @moduledoc """
  This is only used for development and testing.
  """

  @code "MOCK_GITHUB_AUTHORIZE_CODE"
  @url "MOCK_GITHUB_AUTHORIZE_URL"
  @token "MOCK_GITHUB_AUTHORIZE_TOKEN"

  def authorize_url! do
    "/auth/github/callback?code=#{@code}\##{@url}"
  end
  def get_token!(args) do
    code = args[:code]
    if code != @code, do: raise("Incorrect GitHub auth code: #{code}")
    %{token: %{access_token: @token}}
  end
  def get_user!(client) do
    token = client.token.access_token
    if token != @token, do: raise("Incorrect GitHub auth code: #{token}")
    %{body: %{"id" => 23, "login" => "space"}}
  end
end
defmodule Aelita2.GitHubMock.Integration do
  @moduledoc """
  This is only used for development and testing.
  """

  def get_installation_token!(_) do
    raise("unimplemented")
  end
  def get_my_repos!(_) do
    raise("unimplemented")
  end
end
