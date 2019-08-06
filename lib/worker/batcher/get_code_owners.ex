defmodule BorsNG.Worker.Batcher.GetCodeOwners do
  @moduledoc """
  Get the bors configuration from a repository.
  This will use `bors.toml`, if available,
  or it will attempt to infer it from other files in the repo.
  """

  alias BorsNG.GitHub

  @type terror :: :fetch_failed | :parse_failed | :status | :timeout_sec

  @spec get(GitHub.tconn, binary) :: {:ok, BorsNG.CodeOwners.t} | {:error, terror}
  def get(repo_conn, branch) do
    file = GitHub.get_file!(repo_conn, branch, ".github/CODEOWNERS")

    BorsNG.CodeOwnerParser.parse_file(file)
  end

end
