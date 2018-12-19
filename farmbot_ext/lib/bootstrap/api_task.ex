defmodule Farmbot.Bootstrap.APITask do
  @moduledoc """
  Task to ensure Farmbot has synced:
    * Farmbot.Asset.Device
    * Farmbot.Asset.FbosConfig
    * Farmbot.Asset.FirmwareConfig
  """
  alias Ecto.{Changeset, Multi}

  require Farmbot.Logger
  alias Farmbot.API
  alias API.{Reconciler, SyncGroup, EagerLoader}

  alias Farmbot.Asset.{
    Repo,
    Sync
  }

  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :sync_all, []},
      type: :worker,
      restart: :transient,
      shutdown: 500
    }
  end

  @doc false
  def sync_all() do
    sync_changeset = API.get_changeset(Sync)
    sync = Changeset.apply_changes(sync_changeset)

    multi = Multi.new()

    with {:ok, multi} <- Reconciler.sync_group(multi, sync, SyncGroup.group_0()),
         {:ok, _} <- Repo.transaction(multi) do
      auto_sync_change =
        Enum.find_value(multi.operations, fn {{key, _id}, {:changeset, change, []}} ->
          key == :fbos_configs && Changeset.get_change(change, :auto_sync)
        end)

      Farmbot.Logger.success(3, "Successfully synced bootup resources.")

      :ok =
        maybe_auto_sync(sync_changeset, auto_sync_change || Farmbot.Asset.fbos_config().auto_sync)
    end

    :ignore
  end

  # When auto_sync is enabled, do the full sync.
  defp maybe_auto_sync(sync_changeset, true) do
    Farmbot.Logger.busy(3, "bootup auto sync")
    sync = Changeset.apply_changes(sync_changeset)
    multi = Multi.new()

    with {:ok, multi} <- Reconciler.sync_group(multi, sync, SyncGroup.group_1()),
         {:ok, multi} <- Reconciler.sync_group(multi, sync, SyncGroup.group_2()),
         {:ok, multi} <- Reconciler.sync_group(multi, sync, SyncGroup.group_3()),
         {:ok, multi} <- Reconciler.sync_group(multi, sync, SyncGroup.group_4()) do
      Multi.insert(multi, :syncs, sync_changeset)
      |> Repo.transaction()

      Farmbot.Logger.success(3, "bootup auto sync complete")
    else
      error -> Farmbot.Logger.error(3, "bootup auto sync failed #{inspect(error)}")
    end

    :ok
  end

  # When auto_sync is disabled preload the sync.
  defp maybe_auto_sync(sync_changeset, false) do
    Farmbot.Logger.busy(3, "preloading sync")
    sync = Changeset.apply_changes(sync_changeset)
    EagerLoader.preload(sync)
    Farmbot.Logger.success(3, "preloaded sync ok")
    :ok
  end
end
