use Mix.Config

config :bors_github, :server, BorsNG.GitHub.Server
config :bors_github, :oauth2, BorsNG.GitHub.OAuth2

import_config "prod.secret.exs"
