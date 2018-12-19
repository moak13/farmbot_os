defmodule Farmbot.Target.InfoWorker.Supervisor do
  @moduledoc false
  use Supervisor

  alias Farmbot.Target.InfoWorker.{
    DiskUsage,
    MemoryUsage,
    SocTemp,
    Uptime,
    WifiLevel
  }

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init([]) do
    children = [
      DiskUsage,
      MemoryUsage,
      SocTemp,
      Uptime,
      {WifiLevel, ifname: "wlan0"}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
