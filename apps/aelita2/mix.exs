defmodule Aelita2.Mixfile do
  use Mix.Project

  def project do
    [ app: :aelita2,
      version: "0.0.1",
      elixirc_paths: elixirc_paths(Mix.env),
      compilers: [ :phoenix, :gettext ] ++ Mix.compilers,
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      aliases: aliases(),
      deps: deps() ]
  end

  # Configuration for the OTP application.
  def application do
    [ mod: {Aelita2, []},
      extra_applications: [ :logger ] ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: [ "lib", "web", "test/support" ]
  defp elixirc_paths(_),     do: [ "lib", "web" ]

  # Specifies your project dependencies.
  defp deps do
    [ {:ex_link_header, "~> 0.0.5"},
      {:phoenix, "~> 1.2.1"},
      {:phoenix_pubsub, "~> 1.0"},
      {:phoenix_ecto, "~> 3.0"},
      {:postgrex, "~> 0.13.0"},
      {:phoenix_html, "~> 2.6"},
      {:phoenix_live_reload, "~> 1.0", only: :dev},
      {:poison, "~> 2.0"},
      {:gettext, "~> 0.11"},
      {:cowboy, "~> 1.0"},
      {:oauth2, [git: "git://github.com/bors-ng/oauth2.git"]},
      {:httpoison, "~> 0.10.0"},
      {:joken, "~> 1.4"},
      {:jose, "~> 1.8"},
      {:libsodium, "~> 0.0.3", runtime: false},
      {:etoml, [git: "git://github.com/kalta/etoml.git"]},
      {:wobserver, "~> 0.1.5"} ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to create, migrate and run the seeds file at once:
  #
  #     $ mix ecto.setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [ "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "test": ["ecto.create --quiet", "ecto.migrate", "test"] ]
  end
end
