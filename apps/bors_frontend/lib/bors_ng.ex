defmodule BorsNG do
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
      # Start the Ecto repository
      supervisor(BorsNG.Repo, []),
      # Start the endpoint when the application starts
      supervisor(BorsNG.Endpoint, []),
      # worker(BorsNG.Worker, [arg1, arg2, arg3]),
      supervisor(BorsNG.Batcher.Supervisor, []),
      worker(BorsNG.Batcher.Registry, []),
      supervisor(BorsNG.Attemptor.Supervisor, []),
      worker(BorsNG.Attemptor.Registry, []),
      supervisor(Task.Supervisor, [[name: BorsNG.Syncer.Supervisor]]),
      supervisor(Registry, [:unique, BorsNG.Syncer.Registry]),
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :rest_for_one, name: BorsNG.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    BorsNG.Endpoint.config_change(changed, removed)
    :ok
  end
end
