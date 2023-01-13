defmodule BorsNG.Application do
  @moduledoc """
  The top-level OTP application for Bors-NG.
  """

  use Application

  def set_repo do
    repo_module =
      case System.get_env("BORS_DATABASE", "postgresql") do
        "mysql" -> BorsNG.Database.RepoMysql
        _ -> BorsNG.Database.RepoPostgres
      end

    :persistent_term.put(:db_repo, repo_module)
  end

  def fetch_repo do
    :persistent_term.get(:db_repo)
  end

  defp get_log_level_from_env do
    case System.get_env("BORS_LOG_LEVEL") do
      nil -> nil
      level_string -> String.to_existing_atom(level_string)
    end
  end

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    log_level_from_env = get_log_level_from_env()

    # Note: this only works if we do not use `:compile_time_purge_matching` in `config.exs`;
    # otherwise all log level calls we want to ignore actually get purged entirely from the code.
    # Ref: https://hexdocs.pm/logger/1.14.2/Logger.html#module-application-configuration
    if not is_nil(log_level_from_env) do
      Logger.configure(level: log_level_from_env)
    end

    # Define workers and child supervisors to be supervised
    set_repo()

    repo = fetch_repo()

    children = [
      %{
        type: :supervisor,
        id: repo,
        start: {repo, :start_link, []}
      },
      %{
        type: :worker,
        id: Confex.fetch_env!(:bors, :server),
        start: {Confex.fetch_env!(:bors, :server), :start_link, []}
      },
      %{type: :worker, id: BorsNG.Attrs, start: {BorsNG.Attrs, :start_link, []}},
      %{
        type: :supervisor,
        id: BorsNG.Worker.Batcher.Supervisor,
        start: {BorsNG.Worker.Batcher.Supervisor, :start_link, []}
      },
      %{
        type: :worker,
        id: BorsNG.Worker.Batcher.Registry,
        start: {BorsNG.Worker.Batcher.Registry, :start_link, []}
      },
      %{
        type: :supervisor,
        id: BorsNG.Worker.Attemptor.Supervisor,
        start: {BorsNG.Worker.Attemptor.Supervisor, :start_link, []}
      },
      %{
        type: :worker,
        id: BorsNG.Worker.Attemptor.Registry,
        start: {BorsNG.Worker.Attemptor.Registry, :start_link, []}
      },
      %{
        type: :supervisor,
        id: BorsNG.Worker.Syncer.Supervisor,
        start: {Task.Supervisor, :start_link, [[name: BorsNG.Worker.Syncer.Supervisor]]}
      },
      %{
        type: :supervisor,
        id: BorsNG.Worker.Syncer.Registry,
        start: {Registry, :start_link, [:unique, BorsNG.Worker.Syncer.Registry]}
      },
      %{
        type: :supervisor,
        start: {
          Registry,
          :start_link,
          [:unique, BorsNG.Worker.SyncerInstallation.Registry]
        },
        id: Installation
      },
      %{
        type: :worker,
        start: {
          BorsNG.Worker.BranchDeleter,
          :start_link,
          []
        },
        id: BorsNG.Worker.BranchDeleter
      },
      %{
        type: :supervisor,
        start: {
          BorsNG.Endpoint,
          :start_link,
          []
        },
        id: BorsNG.Endpoint
      },
      {Phoenix.PubSub, [name: BorsNG.PubSub, adapter: Phoenix.PubSub.PG2]}
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :rest_for_one, name: BorsNG.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
