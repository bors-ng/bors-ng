use Mix.Config

case System.get_env("BORS_TEST_DATABASE") do
  "mysql" ->
    config :bors, BorsNG.Database.Repo,
      adapter: Ecto.Adapters.MySQL,
      username: "root",
      password: "",
      database: "bors_test",
      hostname: {:system, "MYSQL_HOST", "localhost"},
      pool: Ecto.Adapters.SQL.Sandbox
  _ ->
    config :bors, BorsNG.Database.Repo,
      adapter: Ecto.Adapters.Postgres,
      username: "postgres",
      password: "Postgres1234",
      database: "bors_test",
      hostname: {:system, "POSTGRES_HOST", "localhost"},
      pool: Ecto.Adapters.SQL.Sandbox
end

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bors, BorsNG.Endpoint,
  http: [port: 4001],
  server: false

config :bors, :server, BorsNG.GitHub.ServerMock
config :bors, :oauth2, BorsNG.GitHub.OAuth2Mock
