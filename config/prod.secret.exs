use Mix.Config

config :bors, BorsNG.Database.Repo,
  adapter: Ecto.Adapters.Postgres,
  url: {:system, "DATABASE_URL"},
  pool_size: {:system, :integer, "POOL_SIZE", 10},
  loggers: [{Ecto.LogEntry, :log, []}],
  ssl: {:system, :boolean, "DATABASE_USE_SSL", true}

config :bors, BorsNG.Endpoint,
  http: [port: {:system, "PORT"}],
  url: [
    host: {:system, "PUBLIC_HOST"},
    scheme: "https",
    port: {:system, :integer, "PUBLIC_PORT", 443}
  ],
  check_origin: false,
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true,
  root: ".",
  version: Application.spec(:myapp, :vsn),
  secret_key_base: {:system, "SECRET_KEY_BASE"},
  ssl: {:system, :boolean, "FORCE_SSL", true},
  force_ssl: [rewrite_on: [:x_forwarded_proto]]

config :bors, BorsNG.WebhookParserPlug, webhook_secret: {:system, "GITHUB_WEBHOOK_SECRET"}

config :bors, BorsNG.GitHub.OAuth2,
  client_id: {:system, "GITHUB_CLIENT_ID"},
  client_secret: {:system, "GITHUB_CLIENT_SECRET"}

config :bors, BorsNG.GitHub.Server,
  iss: {:system, :integer, "GITHUB_INTEGRATION_ID"},
  pem: {:system, {Base, :decode64, []}, "GITHUB_INTEGRATION_PEM"}
