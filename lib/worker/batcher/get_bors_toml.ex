defmodule BorsNG.Worker.Batcher.GetBorsToml do
  @moduledoc """
  Get the bors configuration from a repository.
  This will use `bors.toml`, if available,
  or it will attempt to infer it from other files in the repo.
  """

  alias BorsNG.GitHub
  alias BorsNG.Worker.Batcher.BorsToml

  @type terror :: :fetch_failed | :parse_failed | :status | :timeout_sec

  @spec get(GitHub.tconn(), binary) :: {:ok, BorsToml.t()} | {:error, terror}
  def get(repo_conn, branch) do
    toml =
      case GitHub.get_file!(repo_conn, branch, "bors.toml") do
        nil ->
          GitHub.get_file!(repo_conn, branch, ".github/bors.toml")

        toml ->
          toml
      end

    case toml do
      nil ->
        [
          {".travis.yml", "continuous-integration/travis-ci/push"},
          {".appveyor.yml", "continuous-integration/appveyor/branch"},
          {"appveyor.yml", "continuous-integration/appveyor/branch"},
          {"circle.yml", "ci/circleci"},
          {".circleci/config.yml", "ci/circleci%"},
          {"jet-steps.yml", "continuous-integration/codeship"},
          {"jet-steps.json", "continuous-integration/codeship"},
          {"codeship-steps.yml", "continuous-integration/codeship"},
          {"codeship-steps.json", "continuous-integration/codeship"},
          {".semaphore/semaphore.yml", "continuous-integration/semaphoreci"}
        ]
        |> Enum.filter(fn {file, _} ->
          not is_nil(GitHub.get_file!(repo_conn, branch, file))
        end)
        |> Enum.map(fn {_, status} -> status end)
        |> case do
          [] -> {:error, :fetch_failed}
          statuses -> {:ok, %BorsToml{status: statuses}}
        end

      toml ->
        BorsToml.new(toml)
    end
  end
end
