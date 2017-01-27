defmodule Aelita2.GitHubMock do
  @moduledoc """
  This is only used for development and testing.
  """

  @type tconn :: %Aelita2.GitHub.RepoConnection{}

  @spec push!(tconn, binary, binary) :: binary
  def push!(_, sha, _) do
    sha
  end
  @spec get_pr!(tconn, integer | bitstring) :: Aelita2.GitHub.Pr.t
  def get_pr!(_, pr_xref) do
    number = case pr_xref do
      x when is_integer(x) -> x
      x when is_binary(x) -> String.to_integer(x)
    end
    %Aelita2.GitHub.Pr{
      number: number,
      title: "",
      body: "",
      state: :open,
      base_ref: "master",
      head_sha: "NNN",
    }
  end
  @spec copy_branch!(tconn, binary, binary) :: binary
  def copy_branch!(_, _, _) do
    "SOMESHA"
  end
  @spec merge_branch!(tconn, map) :: map
  def merge_branch!(_, _) do
    %{
      commit: "SOMEOTHERSHA",
      tree: "ANOTHERSHA",
    }
  end
  @spec synthesize_commit!(tconn, map) :: binary
  def synthesize_commit!(_, _) do
    "YETANOTHERSHA"
  end
  @spec get_file(tconn, binary, binary) :: binary | nil
  def get_file(r, _, _) do
    case r.repo do
      1 -> nil
      2 -> ~s/status = ["some-status"]/
    end
  end
  @spec post_comment!(tconn, number, binary) :: :ok
  def post_comment!(_, _, _) do
    :ok
  end
  @spec get_commit_status!(tconn, binary) :: %{binary => :running | :ok | :error}
  def get_commit_status!(_, _) do
    %{"some-status" => :ok}
  end
  @spec get_user_by_login(binary, binary) :: {:ok, map} | {:error, atom}
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

  @type t :: Aelita2.GitHub.RepoConnection.t

  @spec connect!(%{installation: number, repo: number}) :: t
  defdelegate connect!(repo_conn), to: Aelita2.GitHub.RepoConnection
end
defmodule Aelita2.GitHubMock.OAuth2 do
  @moduledoc """
  This is only used for development and testing.
  """

  @code "MOCK_GITHUB_AUTHORIZE_CODE"
  @url "MOCK_GITHUB_AUTHORIZE_URL"
  @token "MOCK_GITHUB_AUTHORIZE_TOKEN"
  @avatar "https://cdn.rawgit.com/notriddle/bors-ng/b9e756/icon/bors-eye.svg"

  @type t :: map

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
  @spec get_user!(t) :: map
  def get_user!(client) do
    token = client.token.access_token
    if token != @token, do: raise("Incorrect GitHub auth code: #{token}")
    %{body: %{"id" => 23, "login" => "space", "avatar_url" => @avatar}}
  end
end
defmodule Aelita2.GitHubMock.Integration do
  @moduledoc """
  This is only used for development and testing.
  """

  @spec get_installation_token!(number) :: binary
  def get_installation_token!(installation_xref) do
    case installation_xref do
      123 -> "INST123"
      1 -> "INST"
      69 -> "CCC"
    end
  end
  @spec get_installation_token!(binary) :: [map]
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
