import Config

config :bors, :server, BorsNG.GitHub.Server
config :bors, :oauth2, BorsNG.GitHub.OAuth2
config :oauth2, adapter: Tesla.Adapter.Hackney

import_config "prod.secret.exs"
