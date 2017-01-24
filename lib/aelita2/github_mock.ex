defmodule Aelita2.GitHubMock do
  @moduledoc """
  This is only used for development and testing.
  """

  def push!(_, sha, _) do
    sha
  end
  def get_pr!(_, pr_xref) do
    %{
      "number" => pr_xref,
      "base" => %{
        "ref" => "master"}}
  end
  def copy_branch!(_, _, _) do
    "SOMESHA"
  end
  def merge_branch!(_, _) do
    %{
      commit: "SOMEOTHERSHA",
      tree: "ANOTHERSHA",
    }
  end
  def synthesize_commit!(_, _) do
    "YETANOTHERSHA"
  end
  def get_file(r, _, _) do
    case r.repo do
      1 -> nil
      2 -> ~s/status = ["some-status"]/
    end
  end
  def post_comment!(_, _, _) do
    :ok
  end
  def get_commit_status!(_, _) do
    %{"some-status" => :ok}
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

  def get_installation_token!(installation_xref) do
    case installation_xref do
      123 -> "INST123"
      1 -> "INST"
      69 -> "CCC"
    end
  end
  def get_my_repos!(token) do
    case token do
      "INST123" -> [
        %{
          id: 1,
          name: "test/repo",
          owner: %{
            id: 1,
            login: "user",
            avatar_url: "http://avatar/user",
            type: "User"}}]
      "INST" -> [
        %{
          id: 1,
          name: "test/repo",
          owner: %{
            id: 1,
            login: "user",
            avatar_url: "http://avatar/user",
            type: "User"}},
        %{
          id: 2,
          name: "test/mess",
          owner: %{
            id: 2,
            login: "group",
            avatar_url: nil,
            type: "Organization"}}]
      "CCC" -> []
    end
  end
end
