defmodule Aelita2.Mixfile do
  use Mix.Project

  def project do
    [app: :aelita2,
     version: "0.0.1",
     elixir: "~> 1.2",
     elixirc_paths: elixirc_paths(Mix.env),
     compilers: [:phoenix, :gettext] ++ Mix.compilers,
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     aliases: aliases(),
     deps: deps(),
     dialyzer: [
      flags: [
        "-Wno_unused",
        "-Werror_handling",
        "-Wrace_conditions"]]]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [mod: {Aelita2, []},
     applications: [:phoenix, :phoenix_pubsub, :phoenix_html, :cowboy,
                    :logger, :gettext, :phoenix_ecto, :postgrex, :oauth2,
                    :httpoison, :etoml]]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "web", "test/support"]
  defp elixirc_paths(_),     do: ["lib", "web"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:ex_link_header, "~> 0.0.5"},
      {:phoenix, "~> 1.2.1"},
      {:phoenix_pubsub, "~> 1.0"},
      {:phoenix_ecto, "~> 3.0"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 2.6"},
      {:phoenix_live_reload, "~> 1.0", only: :dev},
      {:poison, "~> 2.0"},
      {:gettext, "~> 0.11"},
      {:cowboy, "~> 1.0"},
      # Point at hex.pm once #84 gets into a release
      {:oauth2, [git: "git://github.com/scrogson/oauth2.git"]},
      {:httpoison, "~> 0.10.0"},
      {:joken, "~> 1.1"},
      {:jose, "~> 1.8"},
      {:libsodium, "~> 0.0.3"},
      {:etoml, [git: "git://github.com/kalta/etoml.git"]},
      {:dogma, "~> 0.1", only: [:dev], runtime: false},
      {:dialyxir, "~> 0.4", only: [:dev], runtime: false},
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to create, migrate and run the seeds file at once:
  #
  #     $ mix ecto.setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    ["ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
     "ecto.reset": ["ecto.drop", "ecto.setup"],
     "test": ["ecto.create --quiet", "ecto.migrate", "test"]]
  end
end
