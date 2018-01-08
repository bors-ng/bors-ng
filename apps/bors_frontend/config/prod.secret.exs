use Mix.Config

config :bors_frontend, BorsNG.Endpoint,
  http: [port: {:system, "PORT"}],
  url: [host: {:system, "PUBLIC_HOST"}, scheme: "https", port: 443],
  check_origin: false,
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true,
  root: ".",
  version: Application.spec(:myapp, :vsn),
  secret_key_base: {:system, "SECRET_KEY_BASE"}

config :bors_frontend, BorsNG.WebhookParserPlug,
  webhook_secret: {:system, "GITHUB_WEBHOOK_SECRET"}
