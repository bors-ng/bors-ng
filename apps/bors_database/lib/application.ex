defmodule BorsNG.Database.Application do
  @moduledoc """
  The top-level OPT application for Bors-NG database.
  """

  use Application

  @pubsub_adapter Application.get_env(:bors_database, :pubsub)[:adapter]
  @pubsub_name Application.get_env(:bors_database, :pubsub)[:name]
  @pubsub_params Application.get_env(:bors_database, :pubsub)[:opts]

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec

    # Define workers and child supervisors to be supervised
    children = [
      # Start the Ecto repository
      supervisor(BorsNG.Database.Repo, []),
      # Start the pubsub registry
      supervisor(@pubsub_adapter, [@pubsub_name, @pubsub_params])
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :rest_for_one, name: BorsNG.Database.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
