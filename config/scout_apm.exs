# This configuration file is used for Scout APM.
# See our help docs at http://help.apm.scoutapp.com for more information.
# config/scout_apm.exs
use Mix.Config

if System.get_env("SCOUT_KEY") do

  config :scout_apm,
    name: "BorsNG", # The app name that will appear within the Scout UI
    key: System.get_env("SCOUT_KEY")

  config :phoenix, :template_engines,
    eex: ScoutApm.Instruments.EExEngine,
    exs: ScoutApm.Instruments.ExsEngine

end
