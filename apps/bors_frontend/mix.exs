defmodule BorsNG.Mixfile do
  use Mix.Project

  def project do
    [
      app: :bors_frontend,
      version: "0.0.4",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixirc_paths: elixirc_paths(Mix.env),
      compilers: [:phoenix, :gettext] ++ Mix.compilers,
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  def application do
    [mod: {BorsNG, []},
      extra_applications: [:logger]]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "web", "test/support"]
  defp elixirc_paths(_),     do: ["lib", "web"]

  # Specifies your project dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.2.1"},
      {:phoenix_ecto, "~> 3.0"},
      {:phoenix_html, "~> 2.6"},
      {:phoenix_live_reload, "~> 1.0", only: :dev},
      {:poison, "~> 2.0"},
      {:gettext, "~> 0.11"},
      {:cowboy, "~> 1.0"},
      {:httpoison, "~> 0.11.0"},
      {:etoml, [git: "git://github.com/kalta/etoml.git"]},
      {:wobserver, "~> 0.1.7"},
      {:bors_github, [in_umbrella: true]},
      {:bors_database, [in_umbrella: true]},
      {:bors_worker, [in_umbrella: true]},
    ]
  end
end
