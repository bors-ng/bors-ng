defmodule Mix.Tasks.Bors.Cleanup do
  use Mix.Task
  import Mix.Ecto
  import Ecto.Query

  @shortdoc "Prune old batches and patches"

  @moduledoc """
  Delete old batches and patches from the database.

  Old patches and batches which are done processing generally are not
  useful to keep around. Deleting them regularly can keep the rows of
  your database tables under the small limits of some database
  providers.

  ## Examples
      mix bors.cleanup --months 6

  ## Command line options
    * `--months` - the integer number of months to keep data
  """

  @doc false
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [months: :integer])

    case opts do
      [] ->
        Mix.shell().info("Pass `--months <integer>' for the number of months to delete")

      [months: months] ->
        Mix.shell().info("Cleaning data older than #{inspect(months)} months")
        negative_months = 0 - months

        Enum.each(repos(), fn repo ->
          ensure_repo(repo, args)
          ensure_migrations_path(repo)
          {:ok, pid, _} = ensure_started(repo, [])

          # Delete all batches older than N months which are done processing
          BorsNG.Database.Repo.delete_all(
            from(p in BorsNG.Database.Batch,
              where:
                p.state in [^:ok, ^:error, ^:canceled] and
                  p.updated_at < datetime_add(^NaiveDateTime.utc_now(), ^negative_months, "month")
            )
          )

          # Delete all the patches which are not open, and older than N months
          BorsNG.Database.Repo.delete_all(
            from(p in BorsNG.Database.Patch,
              where:
                not p.open and
                  p.updated_at < datetime_add(^NaiveDateTime.utc_now(), ^negative_months, "month")
            )
          )

          # Delete all the old crash reports
          BorsNG.Database.Repo.delete_all(
            from(p in BorsNG.Database.Crash,
              where:
                p.updated_at < datetime_add(^NaiveDateTime.utc_now(), ^negative_months, "month")
            )
          )

          repo.stop(pid)
        end)
    end
  end

  def repos, do: Application.get_env(:bors, :ecto_repos, [])
end
