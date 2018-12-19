defmodule Farmbot.AMQP.NervesHubTransport do
  use GenServer
  use AMQP

  alias AMQP.{
    Channel,
    Queue
  }

  require Farmbot.Logger
  require Logger
  alias Farmbot.JSON

  alias Farmbot.AMQP.ConnectionWorker

  @exchange "amq.topic"
  @handle_nerves_hub_msg Application.get_env(:farmbot_ext, __MODULE__)[:handle_nerves_hub_msg]
  @handle_nerves_hub_msg ||
    Mix.raise("""
    Please define a function that will handle NervesHub certs.

        config :farmbot_ext, Farmbot.AMQP.NervesHubTransport,
          handle_nerves_hub_msg: SomeModule
    """)

  @doc "Save certs to persistent storage somewhere."
  @callback configure_certs(binary(), binary()) :: :ok | {:error, term()}

  @doc "Connect to NervesHub."
  @callback connect() :: :ok | {:error, term()}

  defstruct [:conn, :chan, :jwt]
  alias __MODULE__, as: State

  @doc false
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    jwt = Keyword.fetch!(args, :jwt)
    Process.flag(:sensitive, true)
    {:ok, %State{conn: nil, chan: nil, jwt: jwt}, 0}
  end

  def terminate(reason, state) do
    Farmbot.Logger.error(1, "Disconnected from NervesHub AMQP channel: #{inspect(reason)}")
    # If a channel was still open, close it.
    if state.chan, do: AMQP.Channel.close(state.chan)
  end

  def handle_info(:timeout, state) do
    bot = state.jwt.bot
    nerves_hub = bot <> "_nerves_hub"
    route = "bot.#{bot}.nerves_hub"

    with %{} = conn <- ConnectionWorker.connection(),
         {:ok, chan} <- Channel.open(conn),
         :ok <- Basic.qos(chan, global: true),
         {:ok, _} <- Queue.declare(chan, nerves_hub, auto_delete: false, durable: true),
         :ok <- Queue.bind(chan, nerves_hub, @exchange, routing_key: route),
         {:ok, _tag} <- Basic.consume(chan, nerves_hub, self(), []) do
      {:noreply, %{state | conn: conn, chan: chan}}
    else
      nil ->
        {:noreply, %{state | conn: nil, chan: nil}, 5000}

      err ->
        Farmbot.Logger.error(1, "Failed to connect to NervesHub AMQP channel: #{inspect(err)}")
        {:noreply, %{state | conn: nil, chan: nil}, 1000}
    end
  end

  # Confirmation sent by the broker after registering this process as a consumer
  def handle_info({:basic_consume_ok, _}, state) do
    {:noreply, state}
  end

  # Sent by the broker when the consumer is
  # unexpectedly cancelled (such as after a queue deletion)
  def handle_info({:basic_cancel, _}, state) do
    {:stop, :normal, state}
  end

  # Confirmation sent by the broker to the consumer process after a Basic.cancel
  def handle_info({:basic_cancel_ok, _}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, %{routing_key: key} = opts}, state) do
    device = state.jwt.bot
    ["bot", ^device, "nerves_hub"] = String.split(key, ".")
    handle_nerves_hub(payload, opts, state)
  end

  def handle_nerves_hub(payload, options, state) do
    with {:ok, %{"cert" => base64_cert, "key" => base64_key}} <- JSON.decode(payload),
         {:ok, cert} <- Base.decode64(base64_cert),
         {:ok, key} <- Base.decode64(base64_key),
         :ok <- handle_nerves_hub_msg().configure_certs(cert, key),
         :ok <- handle_nerves_hub_msg().connect() do
      :ok = Basic.ack(state.chan, options[:delivery_tag])
      {:noreply, state}
    else
      {:error, reason} ->
        Logger.error(1, "OTA Service failed to configure. #{inspect(reason)}")
        {:noreply, state}

      :error ->
        Logger.error(1, "OTA Service payload invalid. (base64)")
        {:noreply, state}
    end
  end

  defp handle_nerves_hub_msg,
    do: Application.get_env(:farmbot_ext, __MODULE__)[:handle_nerves_hub_msg]
end
