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
  github_integration_url:
    "https://github.com/integrations/bors/installations/new",
  allow_private_repos: System.get_env("ALLOW_PRIVATE_REPOS") == "true"

# Configures the endpoint
config :bors_frontend, BorsNG.Endpoint,
  url: [host: "localhost"],
  secret_key_base:
  "RflEtl3q2wkPracTsiqJXfJwu+PtZ6P65kd5rcA7da8KR5Abc/YjB8aZHE4DBxMG",
  render_errors: [view: BorsNG.ErrorView, accepts: ~w(html json)],
  pubsub: [name: BorsNG.Database.PubSub]

config :wobserver,
  mode: :plug,
  security: BorsNG.WobserverSecurity,
  remote_url_prefix: "/wobserver",
  security_key: :crypto.strong_rand_bytes(128)

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"
