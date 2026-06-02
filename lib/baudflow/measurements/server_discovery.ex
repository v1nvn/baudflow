defmodule Baudflow.Measurements.ServerDiscovery do
  @moduledoc """
  Discovers and selects speedtest servers from the Ookla API.

  Supports:
  - Fetching available servers from the Ookla speedtest.net API
  - Selecting a server for scheduled tests based on preferred/blocked lists
  - Filtering out blocked servers
  """

  @servers_url "https://www.speedtest.net/api/js/servers"

  @doc """
  Fetch available servers from Ookla API.

  Returns a list of maps with :id, :name, :location, :country, :host.
  Returns an empty list on any error.
  """
  @spec list_available_servers(keyword()) :: [map()]
  def list_available_servers(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    case Req.get(@servers_url, params: [limit: limit, engine: "ookla"]) do
      {:ok, %Req.Response{status: 200, body: body}} when is_list(body) ->
        Enum.map(body, &normalize_server/1)

      _ ->
        []
    end
  end

  @doc """
  Select a server ID for a scheduled test based on settings.

  Priority:
  1. Random pick from preferred servers list (if non-empty)
  2. Auto-discover closest servers, filter out blocked, pick the first
  3. Returns nil if no server can be found
  """
  @spec select_server() :: integer() | nil
  def select_server do
    settings = Baudflow.Settings.get_all()
    preferred = parse_server_list(settings["preferred_servers"])
    blocked = parse_server_list(settings["blocked_servers"])

    if preferred != [] do
      Enum.random(preferred)
    else
      servers = list_available_servers()
      allowed = filter_blocked(servers, blocked)

      case List.first(allowed) do
        nil -> nil
        server -> server[:id]
      end
    end
  end

  @doc """
  Filter out blocked servers from a list of server maps.

  Blocked IDs are matched against the :id field of each server map.
  """
  @spec filter_blocked([map()], [integer()]) :: [map()]
  def filter_blocked(servers, blocked_ids) do
    Enum.reject(servers, fn server ->
      server[:id] in blocked_ids
    end)
  end

  @doc """
  Parse a comma-separated string of server IDs into a list of integers.

  Handles nil, empty strings, and whitespace gracefully.
  """
  @spec parse_server_list(String.t() | nil) :: [integer()]
  def parse_server_list(nil), do: []
  def parse_server_list(""), do: []

  def parse_server_list(str) when is_binary(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.to_integer/1)
  end

  defp normalize_server(data) when is_map(data) do
    %{
      id: to_integer(data["id"]),
      name: data["sponsor"] || data["name"] || "",
      location: data["name"] || "",
      country: data["country"] || "",
      host: data["host"] || ""
    }
  end

  defp normalize_server(_), do: nil

  defp to_integer(val) when is_integer(val), do: val

  defp to_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp to_integer(_), do: nil
end
