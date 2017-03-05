defmodule BorsNG.GitHub.Application do
  @moduledoc """
  The top-level OPT application for interacting with GitHub.
  """

  use Application

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec

    # Define workers and child supervisors to be supervised
    children = [
      worker(Application.get_env(:bors_github, :server), []),
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :rest_for_one, name: BorsNG.GitHub.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
