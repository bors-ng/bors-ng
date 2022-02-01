defmodule BorsNG.Application do
  @moduledoc """
  The top-level OPT application for Bors-NG.
  """

  use Application

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec

    # Define workers and child supervisors to be supervised
    children = [
      %{
        type: :supervisor,
        id: BorsNG.Database.Repo,
        start: {BorsNG.Database.Repo, :start_link, []}
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
