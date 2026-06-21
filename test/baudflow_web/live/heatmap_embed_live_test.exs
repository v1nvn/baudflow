defmodule BaudflowWeb.HeatmapEmbedLiveTest do
  use BaudflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Baudflow.Measurements

  describe "embed" do
    test "renders a chrome-less current-month tile (no app nav)", %{conn: conn} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, m} =
        Measurements.create_measurement(%{
          timestamp: now,
          ping_latency: 12.5,
          download_bandwidth: 10_000_000,
          upload_bandwidth: 5_000_000,
          result_id: "embed-1",
          source: "scheduled"
        })

      Measurements.update_health(m, true, nil)

      {:ok, lv, html} = live(conn, ~p"/heatmap/embed")

      # Chrome-less: the app nav (Layouts.app) is not applied.
      refute html =~ ~s(aria-label="Dashboard")
      assert html =~ "Baudflow · This Month"
      assert has_element?(lv, "#heatmap-embed[phx-hook='HeatmapMatrix']")

      today_iso = Date.to_iso8601(DateTime.to_date(now))

      assert_push_event(lv, "heatmap_tile:heatmap-embed", %{cells: cells})
      assert Enum.any?(cells, &(&1.d == today_iso and &1.v == "healthy"))
    end
  end
end
