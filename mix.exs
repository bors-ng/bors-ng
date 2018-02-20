defmodule BorsNg.Mixfile do
  use Mix.Project

  def project do
    [ name: "Bors-NG",
      apps_path: "apps",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps(),
      source_url: "https://github.com/bors-ng/bors-ng",
      homepage_url: "https://bors.tech/",
      docs: [
        main: "hacking",
        extras: [ "HACKING.md", "CONTRIBUTING.md", "README.md" ] ],
      dialyzer: [
        flags: [
          "-Wno_unused",
          "-Werror_handling",
          "-Wrace_conditions" ] ] ]
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
      {:dogma, "~> 0.1", only: [ :dev, :test ], runtime: false},
      {:dialyxir, "~> 0.4", only: [ :dev ], runtime: false},
      {:distillery, "~> 1.0", runtime: false},
      {:edeliver, "~> 1.4.0", runtime: false},
      {:ex_doc, "~> 0.14", only: :dev},
      {:credo, "~> 0.7", only: [:dev, :test]},
      {:confex, "~> 3.3.1"},
      {:postgrex, "~> 0.13.5"},
    ]
  end
end
