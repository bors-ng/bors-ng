use Mix.Config

config :bors_worker, ecto_repos: []

import_config "#{Mix.env}.exs"
