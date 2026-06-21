defmodule Baudflow.Settings do
  @moduledoc """
  Context for application settings (key-value store).
  """
  import Ecto.Query
  alias Baudflow.Repo
  alias Baudflow.Settings.Setting

  @default_settings %{
    "server_id" => "",
    "preferred_servers" => "",
    "blocked_servers" => "",
    "retention_days" => "365",
    "dashboard_points" => "500",
    "threshold_enabled" => "false",
    "threshold_download" => "0",
    "threshold_upload" => "0",
    "threshold_ping" => "0",
    "ping_target" => "1.1.1.1",
    "promised_download_mbps" => "0",
    "promised_upload_mbps" => "0",
    # #21: consecutive breaches before a breach alert fires. 1 = notify on the
    # first breach (the step-0 behavior).
    "breach_notify_streak" => "1",
    # #24/#26: webhook transport. A blank URL disables the channel (one "off"
    # representation); a blank template means "use the built-in Template default".
    "webhook_url" => "",
    "webhook_template" => ""
  }

  @doc "Get a single setting value by key. Falls back to defaults if not stored."
  @spec get(String.t()) :: String.t() | nil
  def get(key) do
    case Repo.get_by(Setting, key: key) do
      %Setting{value: value} -> value
      nil -> Map.get(@default_settings, key)
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

  # --- Typed accessors --------------------------------------------------------

  @doc "Get a setting as an integer. Returns `default` (or nil) when missing or unparseable."
  @spec get_integer(String.t(), integer() | nil) :: integer() | nil
  def get_integer(key, default \\ nil) do
    key |> get() |> parse_integer(default)
  end

  @doc """
  Get a setting as a float. Handles integer-looking strings (e.g. `"1"` → `1.0`).
  Returns `default` (or nil) when missing or unparseable.
  """
  @spec get_float(String.t(), float() | nil) :: float() | nil
  def get_float(key, default \\ nil) do
    key |> get() |> parse_float(default)
  end

  @doc "Get a setting as a boolean. Returns `true` only when the stored value is `\"true\"`."
  @spec get_boolean(String.t()) :: boolean()
  def get_boolean(key) do
    get(key) == "true"
  end

  @doc """
  Get a comma-separated setting as a list of integers.
  Returns `[]` when missing, empty, or entirely unparseable.
  Unparseable entries are silently skipped.
  """
  @spec get_integer_list(String.t()) :: [integer()]
  def get_integer_list(key) do
    case get(key) do
      nil -> []
      "" -> []
      str -> parse_csv_integers(str)
    end
  end

  # --- Update -----------------------------------------------------------------

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

  # --- Private helpers --------------------------------------------------------

  defp parse_integer(nil, default), do: default
  defp parse_integer("", default), do: default

  defp parse_integer(raw, default) when is_binary(raw) do
    case Integer.parse(raw) do
      {int, ""} -> int
      {int, _rest} -> int
      :error -> default
    end
  end

  defp parse_float(nil, default), do: default
  defp parse_float("", default), do: default

  defp parse_float(raw, default) when is_binary(raw) do
    case Float.parse(raw) do
      {f, _} -> f
      :error -> default
    end
  end

  defp parse_csv_integers(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.flat_map(&parse_single_integer/1)
  end

  defp parse_single_integer(entry) do
    case Integer.parse(entry) do
      {int, ""} -> [int]
      _ -> []
    end
  end
end
