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
    ]

    run_batcher = Application.get_env(:aelita2, Aelita2.Batcher)[:run]
    children = if run_batcher do
      children ++ [
        supervisor(Aelita2.Batcher.Supervisor, []),
        worker(Aelita2.Batcher.Registry, []),
      ]
    else
      children
    end

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Aelita2.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    Aelita2.Endpoint.config_change(changed, removed)
    :ok
  end
end
