use Mix.Config

case System.get_env("BORS_TEST_DATABASE_MYSQL") do
  "mysql" ->
    :ok
  _ ->
    config :bors_database, BorsNG.Database.Repo,
      adapter: Ecto.Adapters.Postgres,
      username: "postgres",
      password: "Postgres1234",
      database: "bors_test",
      hostname: System.get_env("POSTGRES_HOST") || "localhost",
      pool: Ecto.Adapters.SQL.Sandbox
end
