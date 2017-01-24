use Mix.Config

config :aelita2, Aelita2.Batcher,
  run: true

config :aelita2, Aelita2.Endpoint,
  http: [port: {:system, "PORT"}],
  url: [host: {:system, "PUBLIC_HOST"}, scheme: "https", port: 443],
  check_origin: false,
  cache_static_manifest: "priv/static/manifest.json",
  secret_key_base: System.get_env("SECRET_KEY_BASE")

config :aelita2, Aelita2.Repo,
  adapter: Ecto.Adapters.Postgres,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: true

config :aelita2, Aelita2.GitHub,
  api: Aelita2.GitHub

config :aelita2, Aelita2.GitHub.OAuth2,
  client_id: System.get_env("GITHUB_CLIENT_ID"),
  client_secret: System.get_env("GITHUB_CLIENT_SECRET"),
  scope: "public_repo user"

config :aelita2, Aelita2.GitHub.Integration,
  iss: String.to_integer(System.get_env("GITHUB_INTEGRATION_ID")),
  pem: Base.decode64!(System.get_env("GITHUB_INTEGRATION_PEM")),
  webhook_secret: System.get_env("GITHUB_WEBHOOK_SECRET")
