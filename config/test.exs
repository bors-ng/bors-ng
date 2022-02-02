import Config

config :bors, BorsNG.Database.RepoMysql,
  adapter: Ecto.Adapters.MyXQL,
  username: "root",
  password: "",
  database: "bors_test",
  hostname: {:system, "MYSQL_HOST", "localhost"},
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "priv/repo"

config :bors, BorsNG.Database.RepoPostgres,
  adapter: Ecto.Adapters.Postgres,
  url: {:system, "DATABASE_URL_TEST", "postgresql://postgres:Postgres1234@localhost/bors_test"},
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "priv/repo"

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bors, BorsNG.Endpoint,
  http: [port: 4001],
  server: false

config :bors, :server, BorsNG.GitHub.ServerMock
config :bors, :oauth2, BorsNG.GitHub.OAuth2Mock
config :bors, :is_test, true

config :bors, :celebrate_new_year, false
