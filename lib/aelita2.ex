defmodule Aelita2 do
  @moduledoc """
  A GitHub integration that merges and tests pull requests
  so that the master branch is never, ever broken.
  """

  use Application

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec

    # Define workers and child supervisors to be supervised
    children = [
      # Start the Ecto repository
      supervisor(Aelita2.Repo, []),
      # Start the endpoint when the application starts
      supervisor(Aelita2.Endpoint, []),
      # worker(Aelita2.Worker, [arg1, arg2, arg3]),
      worker(Application.get_env(:aelita2, Aelita2.GitHub)[:server], []),
      supervisor(Aelita2.Batcher.Supervisor, []),
      worker(Aelita2.Batcher.Registry, []),
      supervisor(Task.Supervisor, [[name: Aelita2.Syncer.Supervisor]]),
      supervisor(Registry, [:unique, Aelita2.Syncer.Registry]),
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :rest_for_one, name: Aelita2.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    Aelita2.Endpoint.config_change(changed, removed)
    :ok
  end
end
