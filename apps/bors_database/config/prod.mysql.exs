use Mix.Config

config :bors_database, BorsNG.Database.Repo,
  adapter: Ecto.Adapters.MySQL,
  username: {:system, "DATABASE_USERNAME"},
  password: {:system, "DATABASE_PASSWORD"},
  hostname: {:system, "DATABASE_HOSTNAME"},
  database: "bors",
  port: 3306,
  pool_size: {:system, :integer, "POOL_SIZE", 10},
  ssl: true
