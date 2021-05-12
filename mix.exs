defmodule BorsNg.Mixfile do
  use Mix.Project

  def project do
    [
      name: "Bors-NG",
      app: :bors,
      version: "0.1.0",
      source_url: "https://github.com/bors-ng/bors-ng",
      homepage_url: "https://bors.tech/",
      docs: [
        main: "hacking",
        extras: ["HACKING.md", "CONTRIBUTING.md", "README.md"]
      ],
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        flags: [
          "-Wno_unused",
          "-Werror_handling",
          "-Wrace_conditions"
        ],
        plt_add_apps: [:mix]
      ]
    ]
  end

  # Configuration for the OTP application.
  def application do
    [mod: {BorsNG.Application, []}, extra_applications: [:logger]]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run ecto setup before running tests.
  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate", "test"]
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
      {:phoenix_ecto, "~> 4.2"},
      {:phoenix_html, "~> 2.14.1"},
      {:phoenix_live_reload, "~> 1.3", only: :dev},
      {:phoenix, "~> 1.5.8"},
      {:phoenix_pubsub, "~> 2.0"},
      {:poison, "~> 3.1"},
      {:jason, "~> 1.0"},
      {:gettext, "~> 0.15"},
      {:cowboy, "~> 1.0"},
      {:plug_cowboy, "~> 1.0"},
      {:tesla, "~> 1.4.0"},
      {:toml, "~> 0.5"},
      {:hackney, "~> 1.12"},
      {:ex_link_header, "~> 0.0.5"},
      {:oauth2, "~> 2.0.0"},
      {:joken, "~> 2.0"},
      {:dialyxir, "~> 1.1.0", runtime: false, only: [:dev]},
      {:distillery, "~> 2.0", runtime: false},
      {:edeliver, "~> 1.5", runtime: false},
      {:ex_doc, "~> 0.18", only: :dev},
      {:credo, "~> 1.0", only: [:dev, :test]},
      {:confex, "~> 3.5.0"},
      {:postgrex, "~> 0.15.8"},
      {:myxql, "~> 0.4"},
      {:ecto, "~> 3.5"},
      {:ecto_sql, "~> 3.0"},
      {:ex_parameterized, "~> 1.3.6", only: [:dev, :test]},
      {:glob, git: "https://github.com/bors-ng/glob.git", commit: "7befe06"}
    ]
  end
end
