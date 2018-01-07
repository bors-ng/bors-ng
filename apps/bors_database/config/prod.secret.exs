use Mix.Config

scout_loggers = if Application.get_env(:scout_apm, :key) do
  [{ScoutApm.Instruments.EctoLogger, :log, []}]
else
  []
end

loggers = [{Ecto.LogEntry, :log, []}] ++ scout_loggers

config :bors_database, BorsNG.Database.Repo,
  adapter: Ecto.Adapters.Postgres,
  url: {:system, "DATABASE_URL"},
  pool_size: {:system, :integer, "POOL_SIZE", 10},
  loggers:  loggers,
  ssl: {:system, :boolean, "DATABASE_USE_SSL", :true}
