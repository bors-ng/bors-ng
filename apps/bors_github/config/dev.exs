use Mix.Config

# On developer boxes, we do not actually talk to GitHub.
# Use the mock instance.
config :bors_github, :server, BorsNG.GitHub.ServerMock
config :bors_github, :oauth2, BorsNG.GitHub.OAuth2Mock

config :bors_github, BorsNG.GitHub.OAuth2,
  client_id: "III",
  client_secret: "YYY"
