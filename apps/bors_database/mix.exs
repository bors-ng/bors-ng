defmodule BorsNG.Database.Mixfile do
  use Mix.Project

  def project do
    [ app: :bors_database,
      version: "0.0.1",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixirc_paths: elixirc_paths(Mix.env),
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      aliases: aliases(),
      deps: deps() ]
  end

  # Configuration for the OTP application.
  def application do
    [ mod: {BorsNG.Database.Application, []},
      extra_applications: [ :logger ] ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: [ "lib", "test/support" ]
  defp elixirc_paths(_),     do: [ "lib" ]

  # Specifies your project dependencies.
  defp deps do
    [ {:postgrex, "~> 0.13.0"},
      {:ecto, "~> 2.1"} ]
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
