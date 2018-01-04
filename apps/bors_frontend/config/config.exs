# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

config :bors_frontend, ecto_repos: []

# General application configuration
config :bors_frontend, BorsNG,
  command_trigger: "bors",
  home_url: "https://bors.tech/",
  allow_private_repos: {:system, :boolean, "ALLOW_PRIVATE_REPOS", false}

# Configures the endpoint
config :bors_frontend, BorsNG.Endpoint,
  url: [host: "localhost"],
  secret_key_base:
  "RflEtl3q2wkPracTsiqJXfJwu+PtZ6P65kd5rcA7da8KR5Abc/YjB8aZHE4DBxMG",
  render_errors: [view: BorsNG.ErrorView, accepts: ~w(html json)],
  pubsub: [name: BorsNG.PubSub, adapter: Phoenix.PubSub.PG2]

config :wobserver,
  mode: :plug,
  security: BorsNG.WobserverSecurity,
  remote_url_prefix: "/wobserver",
  security_key: :crypto.strong_rand_bytes(128)

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"
