use Mix.Config

config :bors, :server, BorsNG.GitHub.Server
config :bors, :oauth2, BorsNG.GitHub.OAuth2

import_config "prod.secret.exs"
