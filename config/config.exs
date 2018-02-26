# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

import_config "scout_apm.exs"

# Configures Elixir's Logger
# Do not include metadata nor timestamps in development logs
case Mix.env do
  :prod ->
    config :logger, level: :info
    config :logger, :console,
      format: "$time $metadata[$level] $message\n",
      metadata: [:request_id]
  :test ->
    config :logger, level: :warn
    config :logger, :console, format: "$message\n"
  _ ->
    config :logger, :console,
      format: "[$level] $message\n"
end

config :bors,
  ecto_repos: [BorsNG.Database.Repo],
  site: "https://api.github.com"

# General application configuration
config :bors, BorsNG,
  command_trigger: "bors",
  home_url: "https://bors.tech/",
  allow_private_repos: {:system, :boolean, "ALLOW_PRIVATE_REPOS", false}

# Configures the endpoint
config :bors, BorsNG.Endpoint,
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
