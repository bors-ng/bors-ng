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
      {:phoenix_ecto, "~> 3.0"},
      {:phoenix_html, "~> 2.14.1"},
      {:phoenix_live_reload, "~> 1.0", only: :dev},
      {:phoenix, "~> 1.4.3"},
      {:phoenix_pubsub, "~> 1.0"},
      {:poison, "~> 3.1"},
      {:gettext, "~> 0.15"},
      {:cowboy, "~> 1.0"},
      {:plug_cowboy, "~> 1.0"},
      {:tesla, "~> 1.3.0"},
      {:toml, "~> 0.5"},
      {:hackney, "~> 1.12"},
      {:ex_link_header, "~> 0.0.5"},
      {:oauth2, "~> 2.0.0"},
      {:joken, "~> 2.0"},
      {:dialyxir,
       git: "https://github.com/jeremyjh/dialyxir.git",
       commit: "78ecd45",
       only: [:dev],
       runtime: false},
      {:distillery, "~> 2.0", runtime: false},
      {:edeliver, "~> 1.5", runtime: false},
      {:ex_doc, "~> 0.18", only: :dev},
      {:credo, "~> 1.0", only: [:dev, :test]},
      {:confex, "~> 3.4.0"},
      {:postgrex, "~> 0.13.5"},
      {:mariaex, "~> 0.8"},
      {:ecto, "~> 2.2"},
      {:ex_parameterized, "~> 1.3.6", only: [:dev, :test]},
      {:glob, git: "https://github.com/lindenbaum/glob.git", commit: "a0de0d0"}
    ]
  end
end
