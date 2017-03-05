defmodule BorsNG.Batcher.GetBorsToml do
  @moduledoc """
  Get the bors configuration from a repository.
  This will use `bors.toml`, if available,
  or it will attempt to infer it from other files in the repo.
  """

  alias BorsNG.GitHub
  alias BorsNG.Batcher.BorsToml

  @type terror :: :fetch_failed | :parse_failed | :status | :timeout_sec

  @spec get(GitHub.tconn, bitstring) :: {:ok, BorsToml.t} | {:error, terror}
  def get(repo_conn, branch) do
    toml = GitHub.get_file!(repo_conn, branch, "bors.toml")
    case toml do
      nil ->
        [
          { ".travis.yml", "continuous-integration/travis-ci/push" },
          { "appveyor.yml", "continuous-integration/appveyor/branch" },
        ]
        |> Enum.filter(fn { file, _ } ->
          not is_nil GitHub.get_file!(repo_conn, branch, file) end)
        |> Enum.map(fn { _, status} -> status end)
        |> case do
          [] -> {:error, :fetch_failed}
          statuses -> {:ok, %BorsToml{ status: statuses }}
        end
      toml ->
        BorsToml.new(toml)
    end
  end

end
