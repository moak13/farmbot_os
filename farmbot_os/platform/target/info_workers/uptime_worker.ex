defmodule Farmbot.Target.UptimeWorker do
  use GenServer
  def start_link(_, opts) do
    GenServer.start_link(__MODULE__, [], opts)
  end

  def init([]) do
    send(self(), :report_uptime)
    {:ok, %{}}
  end

  def handle_info(:report_uptime, state) do
    usage = collect_report()

    if GenServer.whereis(Farmbot.BotState) do
      Farmbot.BotState.report_uptime(usage)
      Process.send_after(self(), :report_uptime, 60_000)
    else
      Process.send_after(self(), :report_uptime, 5000)
    end
    {:noreply, state}
  end

  def collect_report do
    {wall_clock_ms, _last_call} = :erlang.statistics(:wall_clock)
    round(wall_clock_ms * 0.001)
  end
end
