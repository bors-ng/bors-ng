defmodule Aelita2.GitHubMock do
  def copy_branch!(_, _, _, _) do
    raise("unimplemented")
  end
  def merge_branch!(_, _, _, _, _) do
    raise("unimplemented")
  end
  def synthesize_commit!(_, _, _, _, _, _) do
    raise("unimplemented")
  end
  def get_file(_, _, _, _) do
    raise("unimplemented")
  end
  def post_comment!(_, _, _, _) do
    raise("unimplemented")
  end
  def get_commit_status!(_, _, _) do
    raise("unimplemented")
  end
  def get_repo!(_, _) do
    raise("unimplemented")
  end
  def map_state_to_status(state) do
    Aelita2.GitHub.map_state_to_status(state)
  end
end
defmodule Aelita2.GitHubMock.OAuth2 do
  def authorize_url!() do
    "MOCK_GITHUB_AUTHORIZE_URL"
  end
  def get_token!(args) do
    code = args[:code]
    if code != "MOCK_GITHUB_AUTHORIZE_CODE", do: raise("Incorrect GitHub auth code: #{code}")
    %{token: %{access_token: "MOCK_GITHUB_AUTHORIZE_TOKEN"}}
  end
  def get_user!(client) do
    token = client.token.access_token
    if token != "MOCK_GITHUB_AUTHORIZE_TOKEN", do: raise("Incorrect GitHub auth code: #{token}")
    %{body: %{"id" => 23, "login" => "space"}}
  end
  def get_my_repos!(_, _) do
    raise("unimplemented")
  end
end
defmodule Aelita2.GitHubMock.Integration do
  def get_installation_token!(_) do
    raise("unimplemented")
  end
  def get_my_repos!(_) do
    raise("unimplemented")
  end
end
