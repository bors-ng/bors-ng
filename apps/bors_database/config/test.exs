use Mix.Config

config :bors_database, BorsNG.Database.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "Postgres1234",
  database: "aelita2_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox
