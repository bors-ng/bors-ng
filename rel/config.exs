# Import all plugins from `rel/plugins`
# They can then be used by adding `plugin MyPlugin` to
# either an environment, or release definition, where
# `MyPlugin` is the name of the plugin module.
Path.join(["rel", "plugins", "*.exs"])
|> Path.wildcard()
|> Enum.map(&Code.eval_file(&1))

use Distillery.Releases.Config,
  # This sets the default release built by `mix release`
  default_release: :bors,
  # This sets the default environment used by `mix release`
  default_environment: Mix.env()

# For a full list of config options for both releases
# and environments, visit https://hexdocs.pm/distillery/configuration.html

# You may define one or more environments in this file,
# an environment's settings will override those of a release
# when building in that environment, this combination of release
# and environment configuration is called a profile

environment :dev do
  set(dev_mode: true)
  set(include_erts: false)
  set(cookie: :",bs/gp(Pk|Tmx6pyt~J68Sr{09akLIc@04<rqo;2EZ2FaA<E!aeFR_/tgi5Zhw9!")
end

environment :prod do
  set(include_erts: true)
  set(include_src: false)
  set(cookie: :"nprGQlz(g].gBN%dbv?Wah!Mvz<;*FmALJ;z}B|RZ=`36uz:|Qc?P!>k?Q/o[hE~")
end

# You may define one or more releases in this file.
# If you have not set a default release, or selected one
# when running `mix release`, the first release in the file
# will be used by default

release :bors do
  set(version: current_version(:bors))
  set(applications: [bors: :permanent])

  set(
    commands: [
      migrate: "rel/commands/migrate"
    ]
  )

  set(pre_start_hooks: "rel/hooks/pre_start")
end
