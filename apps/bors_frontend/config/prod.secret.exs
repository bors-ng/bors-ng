use Mix.Config

config :bors_frontend, BorsNG.Endpoint,
  http: [port: {:system, "PORT"}],
  url: [host: {:system, "PUBLIC_HOST"}, scheme: "https", port: 443],
  check_origin: false,
  cache_static_manifest: "priv/static/manifest.json",
  secret_key_base: System.get_env("SECRET_KEY_BASE")

config :bors_frontend, BorsNG.WebhookParserPlug,
  webhook_secret: System.get_env("GITHUB_WEBHOOK_SECRET")
