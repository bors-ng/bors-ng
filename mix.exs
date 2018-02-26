defmodule BorsNg.Mixfile do
  use Mix.Project

  def project do
    [ name: "Bors-NG",
      app: :bors,
      version: "0.1.0",
      source_url: "https://github.com/bors-ng/bors-ng",
      homepage_url: "https://bors.tech/",
      docs: [
        main: "hacking",
        extras: [ "HACKING.md", "CONTRIBUTING.md", "README.md" ] ],
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps(),
      aliases: aliases(),
      compilers: [:phoenix, :gettext] ++ Mix.compilers,
      elixirc_paths: elixirc_paths(Mix.env),
      dialyzer: [
        flags: [
          "-Wno_unused",
          "-Werror_handling",
          "-Wrace_conditions" ] ] ]
  end

  # Configuration for the OTP application.
  def application do
    [mod: {BorsNG.Application, []},
      extra_applications: [:logger]]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  # Run ecto setup before running tests.
  defp aliases do
    [
      "test": ["ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options.
  #
  # Dependencies listed here are available only for this project
  # and cannot be accessed from applications inside the apps folder
  defp deps do
    [
      {:phoenix_ecto, "~> 3.0"},
      {:phoenix_html, "~> 2.6"},
      {:phoenix_live_reload, "~> 1.0", only: :dev},
      {:phoenix, "~> 1.3.0"},
      {:phoenix_pubsub, "~> 1.0"},
      {:poison, "~> 2.0"},
      {:gettext, "~> 0.11"},
      {:cowboy, "~> 1.0"},
      {:httpoison, "~> 0.11.0"},
      {:etoml, [git: "git://github.com/kalta/etoml.git"]},
      {:wobserver, "~> 0.1.7"},
      {:hackney, "~> 1.8.6"},
      {:dogma, "~> 0.1", only: [ :dev, :test ], runtime: false},
      {:ex_link_header, "~> 0.0.5"},
      {:oauth2, "~> 0.9.1"},
      {:joken, "~> 1.4"},
      {:dialyxir, "~> 0.4", only: [ :dev ], runtime: false},
      {:distillery, "~> 1.0", runtime: false},
      {:edeliver, "~> 1.4.0", runtime: false},
      {:ex_doc, "~> 0.14", only: :dev},
      {:credo, "~> 0.7", only: [:dev, :test]},
      {:confex, "~> 3.3.1"},
      {:postgrex, "~> 0.13.5"},
      {:mariaex, "~> 0.8"},
      {:ecto, "~> 2.1"},
    ] ++ (
      if System.get_env("SCOUT_KEY") do
        [
          {:scout_apm, "~> 0.0"},
        ]
      else
        []
      end
    )
  end
end
