defmodule BaudflowWeb.HeatmapLive do
  use BaudflowWeb, :live_view

  alias Baudflow.Measurements
  alias Baudflow.Scheduling
  alias BaudflowWeb.HeatCalendar

  @moduledoc """
  Health heatmap as a wall grid of monthly calendar tiles (newest top-left),
  each painted by a `HeatmapMatrix` hook (chartjs-chart-matrix). One unbounded
  query (`Measurements.daily_health/1`) feeds every tile — the wall grid is pure
  view logic over the returned `%{Date => status}` map. The current month also
  lives, compact, on the dashboard; a chrome-less copy for iframe embedding is
  at `/heatmap/embed`.

  Each day's status is derived just-in-time by `Measurements.daily_health/1`
  (verdicts are never stored — see `Baudflow.Measurements.health/1`), so a change
  to the mode/ratio repaints the wall on the next load. Buckets are UTC days, so
  the grouping is offset from the viewer's local evening; each cell's tooltip
  renders the absolute UTC date, which is correct.
  """

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Heatmap", active_page: :heatmap)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    status_by_date = Measurements.daily_health(test_type: "ookla")
    today = Date.utc_today()
    # No data → render just the current (all-empty) month so the page still shows
    # something rather than a blank grid.
    earliest = status_by_date |> Map.keys() |> Enum.min(Date, fn -> today end)

    tiles =
      for {year, month} <- months_descending(earliest, today) do
        HeatCalendar.month_matrix(year, month, status_by_date, tile_id(year, month))
      end

    # Each tile's hook listens for its own event, so push once per tile (not one
    # blob) — payloads stay small and the canvas ids stay stable across re-renders.
    socket =
      tiles
      |> Enum.reduce(socket, fn tile, acc ->
        push_event(acc, "heatmap_tile:#{tile.id}", %{cells: tile.cells, weeks: tile.weeks})
      end)
      |> assign(:tiles, tiles)
      |> assign(:has_data, map_size(status_by_date) > 0)
      |> assign(:unknown_label, unknown_label())

    {:noreply, socket}
  end

  # Months newest-first from `latest`'s month down to `earliest`'s. A descending
  # range yields the right order without a separate sort.
  defp months_descending(%Date{} = earliest, %Date{} = latest) do
    start_idx = latest.year * 12 + (latest.month - 1)
    end_idx = earliest.year * 12 + (earliest.month - 1)

    for idx <- start_idx..end_idx//-1 do
      {div(idx, 12), rem(idx, 12) + 1}
    end
  end

  defp tile_id(year, month) do
    "heat-#{year}-#{String.pad_leading(Integer.to_string(month), 2, "0")}"
  end

  defp unknown_label, do: HeatCalendar.unknown_label(Scheduling.global_thresholds().mode)
end
