defmodule BaudflowWeb.HeatmapEmbedLive do
  use BaudflowWeb, :live_view

  alias Baudflow.Measurements
  alias Baudflow.Scheduling
  alias BaudflowWeb.HeatCalendar

  @moduledoc """
  Chrome-less, current-month-only heatmap for iframe embedding (Home Assistant,
  Grafana, etc.). Deliberately rendered without `<Layouts.app>` — no nav, no
  flash toasts — so only the calendar tile and legend show on the page. The full
  all-months grid (with a link here) lives at `/heatmap`. Read-only: it renders
  the latest state on load; revisit the iframe to refresh.
  """

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    since = HeatCalendar.month_start(today)

    status_by_date = Measurements.daily_health(since: since, test_type: "ookla")
    tile = HeatCalendar.month_matrix(today.year, today.month, status_by_date, "heatmap-embed")

    {:ok,
     socket
     |> assign(:page_title, "Baudflow")
     |> assign(:tile, tile)
     |> assign(:unknown_label, unknown_label())
     |> push_event("heatmap_tile:heatmap-embed", %{cells: tile.cells, weeks: tile.weeks})}
  end

  defp unknown_label, do: HeatCalendar.unknown_label(Scheduling.global_thresholds().mode)
end
