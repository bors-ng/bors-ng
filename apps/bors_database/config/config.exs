# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

config :bors_database,
  ecto_repos: [BorsNG.Database.Repo],
  pubsub: [name: BorsNG.Database.PubSub,
           adapter: Phoenix.PubSub.PG2,
           opts: [pool_size: 4]]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"
