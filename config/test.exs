use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :aelita2, Aelita2.Endpoint,
  http: [port: 4001],
  server: false

config :aelita2, Aelita2.Batcher,
  run: false

# Print only warnings and errors during test
config :logger, level: :warn

# Configure your database
config :aelita2, Aelita2.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "Postgres1234",
  database: "aelita2_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

config :aelita2, Aelita2.GitHub,
  api: Aelita2.GitHubMock
