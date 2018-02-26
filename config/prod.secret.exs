use Mix.Config

scout_loggers = if Application.get_env(:scout_apm, :key) do
  [{ScoutApm.Instruments.EctoLogger, :log, []}]
else
  []
end

loggers = [{Ecto.LogEntry, :log, []}] ++ scout_loggers

config :bors, BorsNG.Database.Repo,
  adapter: Ecto.Adapters.Postgres,
  url: {:system, "DATABASE_URL"},
  pool_size: {:system, :integer, "POOL_SIZE", 10},
  loggers:  loggers,
  ssl: {:system, :boolean, "DATABASE_USE_SSL", true}

config :bors, BorsNG.Endpoint,
  http: [port: {:system, "PORT"}],
  url: [host: {:system, "PUBLIC_HOST"}, scheme: "https", port: 443],
  check_origin: false,
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true,
  root: ".",
  version: Application.spec(:myapp, :vsn),
  secret_key_base: {:system, "SECRET_KEY_BASE"}

config :bors, BorsNG.WebhookParserPlug,
  webhook_secret: {:system, "GITHUB_WEBHOOK_SECRET"}

config :bors, BorsNG.GitHub.OAuth2,
  client_id: {:system, "GITHUB_CLIENT_ID"},
  client_secret: {:system, "GITHUB_CLIENT_SECRET"}

config :bors, BorsNG.GitHub.Server,
  iss: {:system, :integer, "GITHUB_INTEGRATION_ID"},
  pem: {:system, {Base, :decode64, []}, "GITHUB_INTEGRATION_PEM"}
