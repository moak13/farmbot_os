use Mix.Config

data_path = Path.join(["/", "tmp", "farmbot"])
config :farmbot_ext,
  data_path: data_path

config :farmbot_core, Farmbot.Config.Repo,
  adapter: Sqlite.Ecto2,
  loggers: [],
  database: Path.join(data_path, "config-#{Mix.env()}.sqlite3"),
  pool_size: 1

config :farmbot_core, Farmbot.Logger.Repo,
  adapter: Sqlite.Ecto2,
  loggers: [],
  database: Path.join(data_path, "logs-#{Mix.env()}.sqlite3"),
  pool_size: 1

config :farmbot_core, Farmbot.Asset.Repo,
  adapter: Sqlite.Ecto2,
  loggers: [],
  database: Path.join(data_path, "repo-#{Mix.env()}.sqlite3"),
  pool_size: 1

config :farmbot_os,
  ecto_repos: [Farmbot.Config.Repo, Farmbot.Logger.Repo, Farmbot.Asset.Repo],
  platform_children: [
    {Farmbot.Host.Configurator, []}
  ]

config :farmbot_os, :behaviour,
  system_tasks: Farmbot.Host.SystemTasks

config :farmbot_os, Farmbot.System.NervesHub,
  farmbot_nerves_hub_handler: Farmbot.Host.NervesHubHandler

import_config("auth_secret.exs")
