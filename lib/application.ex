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
      supervisor(BorsNG.Database.Repo, []),
      worker(Confex.fetch_env!(:bors, :server), []),
      worker(BorsNG.Attrs, []),
      supervisor(BorsNG.Worker.Batcher.Supervisor, []),
      worker(BorsNG.Worker.Batcher.Registry, []),
      supervisor(BorsNG.Worker.Attemptor.Supervisor, []),
      worker(BorsNG.Worker.Attemptor.Registry, []),
      supervisor(Task.Supervisor, [[name: BorsNG.Worker.Syncer.Supervisor]]),
      supervisor(Registry, [:unique, BorsNG.Worker.Syncer.Registry]),
      supervisor(
        Registry,
        [:unique, BorsNG.Worker.SyncerInstallation.Registry],
        id: Installation
      ),
      worker(BorsNG.Worker.BranchDeleter, []),
      supervisor(BorsNG.Endpoint, [])
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :rest_for_one, name: BorsNG.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
