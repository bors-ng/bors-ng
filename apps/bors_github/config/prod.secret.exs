use Mix.Config

config :bors_github, BorsNG.GitHub.OAuth2,
  client_id: System.get_env("GITHUB_CLIENT_ID"),
  client_secret: System.get_env("GITHUB_CLIENT_SECRET")

config :bors_github, BorsNG.GitHub.Server,
  iss: String.to_integer(System.get_env("GITHUB_INTEGRATION_ID")),
  pem: Base.decode64!(System.get_env("GITHUB_INTEGRATION_PEM"))
