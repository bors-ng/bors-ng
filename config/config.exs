# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# General application configuration
config :aelita2,
  ecto_repos: [Aelita2.Repo]

config :aelita2, Aelita2.GitHub,
  require_visibility: :public

# Configures the endpoint
config :aelita2, Aelita2.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "RflEtl3q2wkPracTsiqJXfJwu+PtZ6P65kd5rcA7da8KR5Abc/YjB8aZHE4DBxMG",
  render_errors: [view: Aelita2.ErrorView, accepts: ~w(html json)],
  pubsub: [name: Aelita2.PubSub,
           adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"
