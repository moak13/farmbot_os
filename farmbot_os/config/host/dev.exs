use Mix.Config

data_path = Path.join(["/", "tmp", "farmbot"])
config :farmbot_ext,
  data_path: data_path

config :farmbot_core, Farmbot.Config.Repo,
  adapter: Sqlite.Ecto2,
  loggers: [],
  pool_size: 1,
  database: Path.join(data_path, "config-#{Mix.env()}.sqlite3")

config :farmbot_core, Farmbot.Logger.Repo,
  adapter: Sqlite.Ecto2,
  loggers: [],
  database: Path.join(data_path, "logs-#{Mix.env()}.sqlite3")

config :farmbot_core, Farmbot.Asset.Repo,
  adapter: Sqlite.Ecto2,
  loggers: [],
  database: Path.join(data_path, "repo-#{Mix.env()}.sqlite3")

config :farmbot_os,
  ecto_repos: [Farmbot.Config.Repo, Farmbot.Logger.Repo, Farmbot.Asset.Repo],
  platform_children: [
    {Farmbot.Host.Configurator, []}
  ]

config :farmbot_os, :behaviour,
  system_tasks: Farmbot.Host.SystemTasks

config :farmbot_os, Farmbot.System.NervesHub,
  farmbot_nerves_hub_handler: Farmbot.Host.NervesHubHandler

config :farmbot_core, :behaviour,
  leds_handler: Farmbot.Leds.StubHandler,
  pin_binding_handler: Farmbot.PinBinding.StubHandler,
  celery_script_io_layer: Farmbot.OS.IOLayer,
  firmware_handler: Farmbot.Firmware.UartHandler

config :farmbot_core, :uart_handler, tty: "/dev/ttyACM0"
import_config("auth_secret.exs")
