use Mix.Config

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with brunch.io to recompile .js and .css sources.
config :aelita2, Aelita2.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [node: ["node_modules/brunch/bin/brunch", "watch", "--stdin",
                    cd: Path.expand("../", __DIR__)]]

# On developer boxes, we do not actually talk to GitHub.
# Use the mock instance, and do not run the batcher.
# To test these, compile in prod mode.
config :aelita2, Aelita2.GitHub,
  api: Aelita2.GitHubMock

config :aelita2, Aelita2.GitHub.Integration,
  webhook_secret: "XXX"

config :aelita2, Aelita2.GitHub.OAuth2,
  client_id: "III",
  client_secret: "YYY",
  scope: "public_repo user"

config :aelita2, Aelita2.Batcher,
  run: false

# Watch static and templates for browser reloading.
config :aelita2, Aelita2.Endpoint,
  live_reload: [
    patterns: [
      ~r{priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$},
      ~r{priv/gettext/.*(po)$},
      ~r{web/views/.*(ex)$},
      ~r{web/templates/.*(eex)$}
    ]
  ]

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Configure your database
config :aelita2, Aelita2.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "Postgres1234",
  database: "aelita2_dev",
  hostname: "localhost",
  pool_size: 10
