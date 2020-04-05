# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# Configures Elixir's Logger
# Do not include metadata nor timestamps in development logs
case Mix.env() do
  :prod ->
    config :logger, level: :info

    config :logger, :console,
      format: "$time $metadata[$level] $message\n",
      metadata: [:request_id, :pid]

  :test ->
    config :logger, level: :warn
    config :logger, :console, format: "$message\n"

  _ ->
    config :logger, :console,
      format: "[$level] $message\n",
      metadata: [:request_id, :pid]
end

config :bors,
  ecto_repos: [BorsNG.Database.Repo],
  api_github_root: {:system, :string, "GITHUB_URL_ROOT_API", "https://api.github.com"},
  html_github_root: {:system, :string, "GITHUB_URL_ROOT_HTML", "https://github.com"},
  api_github_timeout: {:system, :integer, "GITHUB_API_TIMEOUT", 10_000}

# General application configuration
config :bors, BorsNG,
  command_trigger: {:system, :string, "COMMAND_TRIGGER", "bors"},
  home_url: "https://bors.tech/",
  allow_private_repos: {:system, :boolean, "ALLOW_PRIVATE_REPOS", false},
  dashboard_header_html:
    {:system, :string, "DASHBOARD_HEADER_HTML",
     """
           <a class=header-link href="https://bors.tech">Home</a>
           <a class=header-link href="https://forum.bors.tech">Forum</a>
           <a class=header-link href="https://bors.tech/documentation/getting-started/">Docs</a>
           <b class=header-link>Dashboard</b>
     """},
  dashboard_footer_html:
    {:system, :string, "DASHBOARD_FOOTER_HTML",
     """
         This service is provided for free on a best-effort basis.
     """}

# Configures the endpoint
config :bors, BorsNG.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "RflEtl3q2wkPracTsiqJXfJwu+PtZ6P65kd5rcA7da8KR5Abc/YjB8aZHE4DBxMG",
  render_errors: [view: BorsNG.ErrorView, accepts: ~w(html json)],
  pubsub: [name: BorsNG.PubSub, adapter: Phoenix.PubSub.PG2]

# Overridden by the test config to avoid date-specific behavior
config :bors, :celebrate_new_year, true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
