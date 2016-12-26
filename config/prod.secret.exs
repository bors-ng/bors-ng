use Mix.Config

config :aelita2, Aelita2,
  activation_phrase: "@aelita-mergebot r+"

config :aelita2, Aelita2.Endpoint,
  http: [port: {:system, "PORT"}],
  url: [host: "sheltered-savannah-39730.herokuapp.com", port: 80],
  cache_static_manifest: "priv/static/manifest.json",
  secret_key_base: System.get_env("SECRET_KEY_BASE")

config :aelita2, Aelita2.Repo,
  adapter: Ecto.Adapters.Postgres,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: true

config :aelita2, Aelita2.OAuth2.GitHub,
  client_id: System.get_env("GITHUB_CLIENT_ID"),
  client_secret: System.get_env("GITHUB_CLIENT_SECRET"),
  scope: "public_repo user",
  require_visibility: :public

config :aelita2, Aelita2.Integration.GitHub,
  iss: String.to_integer(System.get_env("GITHUB_INTEGRATION_ID")),
  pem: Base.decode64!(System.get_env("GITHUB_INTEGRATION_PEM")),
  webhook_secret: System.get_env("GITHUB_WEBHOOK_SECRET")
