use Mix.Config

config :bors_github, BorsNG.GitHub.OAuth2,
  client_id: {:system, "GITHUB_CLIENT_ID"},
  client_secret: {:system, "GITHUB_CLIENT_SECRET"}

config :bors_github, BorsNG.GitHub.Server,
  iss: {:system, :integer, "GITHUB_INTEGRATION_ID"},
  pem: {:system, {Base, :decode64, []}, "GITHUB_INTEGRATION_PEM"}
