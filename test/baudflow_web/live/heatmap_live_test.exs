defmodule BaudflowWeb.HeatmapLiveTest do
  use BaudflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Baudflow.Measurements

  # `assert_push_event` pins the event name into a `receive` match, so it must be
  # a literal. The page's per-tile events have dynamic ids (`heat-YYYY-MM`), so
  # here we assert DOM wiring (a canvas + HeatmapMatrix hook per month and the
  # embed link); the pushed cell payload is asserted end-to-end on the literal-id
  # consumers - see HeatmapEmbedLiveTest and the dashboard tile test.

  describe "wall grid" do
    test "renders a tile for each month with data and links to the embed view", %{conn: conn} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      # 40 days back always lands in a strictly earlier month, so two data months
      # (months between them with no data render as all-empty tiles too).
      prev = DateTime.add(now, -40 * 24 * 3600, :second)

      {:ok, _m1} =
        Measurements.create_measurement(valid_attrs(timestamp: now, result_id: "hm-now"))

      {:ok, _m2} =
        Measurements.create_measurement(valid_attrs(timestamp: prev, result_id: "hm-prev"))

      {:ok, lv, html} = live(conn, ~p"/heatmap")

      assert html =~ "Health Heatmap"
      assert html =~ "Embed view"
      assert has_element?(lv, "##{tile_id(now)}[phx-hook='HeatmapMatrix']")
      assert has_element?(lv, "##{tile_id(prev)}[phx-hook='HeatmapMatrix']")
    end

    test "with no data, still renders the current month tile", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/heatmap")

      assert html =~ "No speed tests recorded yet"
      assert has_element?(lv, "##{tile_id(Date.utc_today())}[phx-hook='HeatmapMatrix']")
    end
  end

  # --- Helpers ---

  defp tile_id(datetime_or_date) do
    date =
      case datetime_or_date do
        %DateTime{} -> DateTime.to_date(datetime_or_date)
        %Date{} = d -> d
      end

    "heat-#{date.year}-#{String.pad_leading(Integer.to_string(date.month), 2, "0")}"
  end

  defp valid_attrs(overrides) do
    %{
      timestamp: Keyword.get(overrides, :timestamp, ~U[2024-01-01 00:00:00Z]),
      ping_latency: Keyword.get(overrides, :ping_latency, 12.5),
      download_bandwidth: Keyword.get(overrides, :download_bandwidth, 10_000_000),
      upload_bandwidth: Keyword.get(overrides, :upload_bandwidth, 5_000_000),
      result_id: Keyword.get(overrides, :result_id, "test-result-1"),
      source: Keyword.get(overrides, :source, "scheduled")
    }
  end
end
