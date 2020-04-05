defmodule BorsNG.Database.Migrate do
  @moduledoc """
  Custom Ecto database migration task to be used in compiled releases.

  Since Mix tasks are not available after compiling, implement our own version
  of `mix ecto.create` and `mix ecto.migrate`.

  `BorsNG.Database.Migrate.run_standalone` should be called from external
  scripts to perform the required work and exit afterwards.
  `BorsNG.Database.Migrate.up` should be called to run the migrations but
  continue running normally afterwards.
  """

  def repos, do: Application.get_env(:bors, :ecto_repos, [])

  @start_apps [
    :crypto,
    :ssl,
    :postgrex,
    :ecto,
    :confex
  ]

  def run_standalone do
    up()

    :init.stop()
  end

  def up do
    # Hack around https://forum.bors.tech/t/database-not-migrated/145
    # Instead of trying to start the :bors app,
    # which won't start because the database isn't set up yet,
    # we start the Ecto Repo directly.
    Application.load(:bors)
    Enum.each(@start_apps, &Application.ensure_all_started/1)
    Enum.each(repos(), & &1.start_link(pool_size: 1))

    Enum.each(repos(), fn repo ->
      case create_storage_for(repo) do
        :seed ->
          run_migrations_for(repo)
          run_seeds_for(repo)

        :migrate ->
          run_migrations_for(repo)
      end
    end)
  end

  def create_storage_for(repo) do
    case repo.__adapter__.storage_up(repo.config) do
      :ok ->
        :seed

      {:error, :already_up} ->
        :migrate

      {:error, term} when is_binary(term) ->
        raise RuntimeError,
              "The database for #{inspect(repo)} couldn't be " <>
                "created: #{term}"

      {:error, term} ->
        raise RuntimeError,
              "The database for #{inspect(repo)} couldn't be " <>
                "created: #{inspect(term)}"
    end
  end

  def run_migrations_for(repo) do
    app = Keyword.get(repo.config, :otp_app)
    IO.puts("Running migrations for #{app}")

    Ecto.Migrator.run(repo, migrations_path(repo), :up, all: true)
  end

  def run_seeds_for(repo) do
    seed_script = seeds_path(repo)

    if File.exists?(seed_script) do
      app = Keyword.get(repo.config, :otp_app)
      IO.puts("Running seed script for #{app}")

      Code.eval_file(seed_script)
    end
  end

  def migrations_path(repo), do: priv_path_for(repo, "migrations")

  def seeds_path(repo), do: priv_path_for(repo, "seeds.exs")

  def priv_dir(app), do: :code.priv_dir(app)

  def priv_path_for(repo, filename) do
    app = Keyword.get(repo.config, :otp_app)
    repo_underscore = repo |> Module.split() |> List.last() |> Macro.underscore()
    Path.join([priv_dir(app), repo_underscore, filename])
  end
end
