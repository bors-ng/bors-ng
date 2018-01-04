use Mix.Config

case System.get_env("BORS_TEST_DATABASE") do
  "mysql" ->
    config :bors_database, BorsNG.Database.Repo,
      adapter: Ecto.Adapters.MySQL,
      username: "root",
      password: "",
      database: "bors_test",
      hostname: {:system, "MYSQL_HOST", "localhost"},
      pool: Ecto.Adapters.SQL.Sandbox
  _ ->
    config :bors_database, BorsNG.Database.Repo,
      adapter: Ecto.Adapters.Postgres,
      username: "postgres",
      password: "Postgres1234",
      database: "bors_test",
      hostname: {:system, "POSTGRES_HOST", "localhost"},
      pool: Ecto.Adapters.SQL.Sandbox
end
