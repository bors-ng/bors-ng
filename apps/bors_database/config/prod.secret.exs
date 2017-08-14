use Mix.Config

scout_loggers = if Application.get_env(:scout_apm, :key) do
  [{ScoutApm.Instruments.EctoLogger, :log, []}]
else
  []
end

loggers = [{Ecto.LogEntry, :log, []}] ++ scout_loggers

config :bors_database, BorsNG.Database.Repo,
  adapter: Ecto.Adapters.Postgres,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: true,
  loggers:  loggers
