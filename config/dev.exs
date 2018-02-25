use Mix.Config

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with brunch.io to recompile .js and .css sources.
config :bors, BorsNG.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [node: ["node_modules/brunch/bin/brunch", "watch", "--stdin",
                    cd: Path.expand("../", __DIR__)]]

config :bors, BorsNG.WebhookParserPlug,
  webhook_secret: "XXX"

# Watch static and templates for browser reloading.
config :bors, BorsNG.Endpoint,
  live_reload: [
    patterns: [
      ~r{priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$},
      ~r{priv/gettext/.*(po)$},
      ~r{web/views/.*(ex)$},
      ~r{web/templates/.*(eex)$}
    ]
  ]

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20
config :bors, BorsNG.Database.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "Postgres1234",
  database: "bors_dev",
  hostname: {:system, "POSTGRES_HOST", "localhost"},
  pool_size: 10

# On developer boxes, we do not actually talk to GitHub.
# Use the mock instance.
config :bors, :server, BorsNG.GitHub.ServerMock
config :bors, :oauth2, BorsNG.GitHub.OAuth2Mock

config :bors, BorsNG.GitHub.OAuth2,
  client_id: "III",
  client_secret: "YYY"
