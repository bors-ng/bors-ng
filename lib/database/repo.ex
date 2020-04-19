defmodule BorsNG.Database.Repo do
  @moduledoc """
  An ecto data repository;
  this process interacts with your persistent database.

  Do not confuse this with a GitHub repo.
  We call those `Project`s internally.
  """

  use Ecto.Repo, otp_app: :bors

  def init(_, config) do
    # Backwards compatibility hack: if POSTGRES_HOST is set, and the database URL is left at default,
    # use the older configuration.
    config = Confex.Resolver.resolve!(config)
    no_host = is_nil(System.get_env("POSTGRES_HOST"))

    config =
      case config[:url] do
        _ when no_host ->
          config

        "postgresql://postgres:Postgres1234@localhost/bors_dev" ->
          [
            adapter: Ecto.Adapters.Postgres,
            username: "postgres",
            password: "Postgres1234",
            database: "bors_dev",
            hostname: {:system, "POSTGRES_HOST", "localhost"},
            pool_size: 10
          ]

        "postgresql://postgres:Postgres1234@localhost/bors_test" ->
          [
            adapter: Ecto.Adapters.Postgres,
            username: "postgres",
            password: "Postgres1234",
            database: "bors_test",
            hostname: {:system, "POSTGRES_HOST", "localhost"},
            pool_size: 10
          ]
      end

    {:ok, config}
  end
end
