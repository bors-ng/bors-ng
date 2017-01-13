defmodule Aelita2.GitHub.RepoConnection do
  @moduledoc """
  A running token that's authorized to access a corresponding repo.
  This is the first argument to most GitHub API functions.
  Note that this can't be store indefinitely, because the token will expire.
  """

  defstruct token: "", repo: 0

  @github_api Application.get_env(:aelita2, Aelita2.GitHub)[:api]

  def connect!(%{installation: installation, repo: repo}) do
    token = @github_api.Integration.get_installation_token!(installation)
    %Aelita2.GitHub.RepoConnection{token: token, repo: repo}
  end
end
