defmodule BorsNG.Worker.Mixfile do
  use Mix.Project

  def project do
    [
      app: :bors_worker,
      version: "0.0.4",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixirc_paths: elixirc_paths(Mix.env),
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  def application do
    [mod: {BorsNG.Worker.Application, []},
      extra_applications: [:logger]]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  # Specifies your project dependencies.
  defp deps do
    [
      {:etoml, [git: "git://github.com/kalta/etoml.git"]},
      {:bors_github, [in_umbrella: true]},
      {:bors_database, [in_umbrella: true]}
    ]
  end
end
