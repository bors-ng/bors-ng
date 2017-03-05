# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# By default, the umbrella project as well as each child
# application will require this configuration file, ensuring
# they all use the same configuration. While one could
# configure all applications here, we prefer to delegate
# back to each application for organization purposes.
import_config "../apps/*/config/config.exs"

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
