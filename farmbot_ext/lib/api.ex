defmodule Farmbot.API do
  alias Farmbot.{API, JSON, JWT}
  alias Farmbot.Asset.StorageAuth
  alias Farmbot.BotState
  alias BotState.JobProgress.Percent
  require Farmbot.Logger
  import Farmbot.Config, only: [get_config_value: 3]

  use Tesla
  alias Tesla.Multipart

  # adapter(Tesla.Adapter.Hackney)
  plug(Tesla.Middleware.JSON, decode: &JSON.decode/1, encode: &JSON.encode/1)
  plug(Tesla.Middleware.FollowRedirects)
  # plug(Tesla.Middleware.Logger)

  @doc false
  def client do
    binary_token = get_config_value(:string, "authorization", "token")
    {:ok, tkn} = JWT.decode(binary_token)

    uri = Map.fetch!(tkn, :iss) |> URI.parse()
    url = (uri.scheme || "https") <> "://" <> uri.host <> ":" <> to_string(uri.port)

    Tesla.build_client([
      {Tesla.Middleware.BaseUrl, url},
      {Tesla.Middleware.Headers,
       [
         {"content-type", "application/json"},
         {"authorization", "Bearer: " <> binary_token},
         {"user-agent", "farmbot-os"}
       ]}
    ])
  end

  def storage_client(%StorageAuth{url: url}) do
    Tesla.build_client(
      [
        {Tesla.Middleware.BaseUrl, "https:" <> url},
        {Tesla.Middleware.Headers,
         [
           {"user-agent", "farmbot-os"}
         ]}
      ],
      [
        {Tesla.Middleware.FormUrlencoded, []}
      ]
    )
  end

  @file_chunk 4096
  @progress_steps 50

  def upload_image(image_filename, meta \\ %{}) do
    storage_auth =
      %StorageAuth{form_data: form_data} =
      API.get_changeset(StorageAuth)
      |> Ecto.Changeset.apply_changes()

    content_length = :filelib.file_size(image_filename)
    {:ok, pid} = Agent.start_link(fn -> 0 end)

    stream =
      image_filename
      |> File.stream!([], @file_chunk)
      |> Stream.each(fn chunk ->
        Agent.update(pid, fn sent ->
          size = sent + byte_size(chunk)
          prog = put_progress(size, content_length)
          BotState.set_job_progress(image_filename, prog)
          size
        end)
      end)

    mp =
      Multipart.new()
      |> Multipart.add_field("key", form_data.key)
      |> Multipart.add_field("acl", form_data.acl)
      |> Multipart.add_field("policy", form_data.policy)
      |> Multipart.add_field("signature", form_data.signature)
      |> Multipart.add_field("Content-Type", form_data."Content-Type")
      |> Multipart.add_field("GoogleAccessId", form_data."GoogleAccessId")
      |> Multipart.add_file_content(stream, Path.basename(image_filename), name: "file")

    storage_resp =
      storage_auth
      |> API.storage_client()
      |> API.request(
        method: String.to_existing_atom(String.downcase(storage_auth.verb)),
        body: mp
      )

    with {:ok, %{url: url, status: s}} when s > 199 and s < 300 <- storage_resp,
         attachment_url <- Path.join(url, form_data.key),
         client <- API.client(),
         body <- %{attachment_url: attachment_url, meta: meta},
         {:ok, %{status: s}} = r when s > 199 and s < 300 <- API.post(client, "/api/images", body) do
      Farmbot.BotState.set_job_progress(image_filename, %Percent{percent: 100, status: :complete})
      r
    else
      er ->
        Farmbot.Logger.error(1, "Failed to upload image")
        Farmbot.BotState.set_job_progress(image_filename, %Percent{percent: -1, status: :error})
        er
    end
  end

  def put_progress(size, max) do
    fraction = size / max
    completed = trunc(fraction * @progress_steps)
    percent = trunc(fraction * 100)
    unfilled = @progress_steps - completed

    IO.write(
      :stderr,
      "\r|#{String.duplicate("=", completed)}#{String.duplicate(" ", unfilled)}| #{percent}% (#{
        bytes_to_mb(size)
      } / #{bytes_to_mb(max)}) MB"
    )

    status = if percent == 100, do: :complete, else: :working

    %Percent{
      status: status,
      percent: percent
    }
  end

  defp bytes_to_mb(bytes) do
    trunc(bytes / 1024 / 1024)
  end

  @doc "helper for `GET`ing a path."
  def get_body!(path) do
    API.get!(API.client(), path)
    |> Map.fetch!(:body)
  end

  @doc "helper for `GET`ing api resources."
  def get_changeset(module) when is_atom(module) do
    get_changeset(struct(module))
  end

  def get_changeset(%module{} = data) do
    get_body!(module.path())
    |> case do
      %{} = single ->
        module.changeset(data, single)

      many when is_list(many) ->
        Enum.map(many, &module.changeset(data, &1))
    end
  end

  @doc "helper for `GET`ing api resources."
  def get_changeset(asset, path)

  # Hacks for dealing with these resources not having #show
  def get_changeset(Farmbot.Asset.FbosConfig, _),
    do: get_changeset(Farmbot.Asset.FbosConfig)

  def get_changeset(Farmbot.Asset.FirmwareConfig, _),
    do: get_changeset(Farmbot.Asset.FirmwareConfig)

  def get_changeset(%Farmbot.Asset.FbosConfig{} = data, _),
    do: get_changeset(data)

  def get_changeset(%Farmbot.Asset.FirmwareConfig{} = data, _),
    do: get_changeset(data)

  def get_changeset(module, path) when is_atom(module) do
    get_changeset(struct(module), path)
  end

  def get_changeset(%module{} = data, path) do
    get_body!(Path.join(module.path(), to_string(path)))
    |> case do
      %{} = single ->
        module.changeset(data, single)

      many when is_list(many) ->
        Enum.map(many, &module.changeset(data, &1))
    end
  end
end
