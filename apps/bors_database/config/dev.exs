use Mix.Config

config :bors_database, BorsNG.Database.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "Postgres1234",
  database: "bors_dev",
  hostname: System.get_env("POSTGRES_HOST") || "localhost",
  pool_size: 10
