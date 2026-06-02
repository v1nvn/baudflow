defmodule Baudflow.Settings do
  @moduledoc """
  Context for application settings (key-value store).
  """
  import Ecto.Query
  alias Baudflow.Repo
  alias Baudflow.Settings.Setting

  @default_settings %{
    "schedule_cron" => "0 * * * *",
    "server_id" => "",
    "preferred_servers" => "",
    "blocked_servers" => "",
    "retention_days" => "365",
    "degradation_threshold" => "0.5",
    "dashboard_points" => "500",
    "threshold_enabled" => "false",
    "threshold_download" => "0",
    "threshold_upload" => "0",
    "threshold_ping" => "0"
  }

  @doc "Get a single setting value by key. Returns nil if not found."
  @spec get(String.t()) :: String.t() | nil
  def get(key) do
    case Repo.get_by(Setting, key: key) do
      %Setting{value: value} -> value
      nil -> nil
    end
  end

  @doc "Get all settings as a map. Missing keys are filled with defaults."
  @spec get_all() :: %{String.t() => String.t()}
  def get_all do
    stored =
      from(s in Setting, select: {s.key, s.value})
      |> Repo.all()
      |> Map.new()

    Map.merge(@default_settings, stored)
  end

  @doc "Update all settings from a map. Upserts each key-value pair. Returns :ok."
  @spec update_all(%{String.t() => String.t()}) :: :ok
  def update_all(settings) when is_map(settings) do
    Enum.each(settings, fn {key, value} ->
      %Setting{}
      |> Setting.changeset(%{key: key, value: value})
      |> Repo.insert(
        on_conflict: [set: [value: value, updated_at: DateTime.utc_now()]],
        conflict_target: :key
      )
    end)

    :ok
  end
end
