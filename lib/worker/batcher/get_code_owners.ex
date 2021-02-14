defmodule BorsNG.Worker.Batcher.GetCodeOwners do
  @moduledoc """
  Get the CODEOWNERS file from the repository
  """

  alias BorsNG.GitHub

  @type terror :: :fetch_failed | :parse_failed | :status | :timeout_sec

  @spec get(GitHub.tconn(), binary) :: {:ok, BorsNG.CodeOwners.t()} | {:error, terror}
  def get(repo_conn, branch) do
    file =
      Enum.find_value(["CODEOWNERS", "docs/CODEOWNERS", ".github/CODEOWNERS"], fn path ->
        GitHub.get_file!(repo_conn, branch, path)
      end)

    BorsNG.CodeOwnerParser.parse_file(file)
  end
end
