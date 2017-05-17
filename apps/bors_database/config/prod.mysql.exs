use Mix.Config

config :bors_database, BorsNG.Database.Repo,
  adapter: Ecto.Adapters.MySQL,
  username: System.get_env("DATABASE_USERNAME"),
  password: System.get_env("DATABASE_PASSWORD"),
  hostname: System.get_env("DATABASE_HOSTNAME"),
  database: "bors",
  port: 3306,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: true
