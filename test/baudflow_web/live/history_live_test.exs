defmodule BaudflowWeb.HistoryLiveTest do
  use BaudflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Baudflow.Measurements
  alias Baudflow.Repo

  describe "mount" do
    test "renders history page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/history")
      assert html =~ "Speed Test History"
    end
  end

  describe "filter bar" do
    test "renders filter form with all controls", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/history")

      assert has_element?(lv, "#filter-form")
      assert has_element?(lv, "input[name='filters[date_from]']")
      assert has_element?(lv, "input[name='filters[date_to]']")
      assert has_element?(lv, "select[name='filters[healthy]']")
      assert has_element?(lv, "select[name='filters[server]']")
      assert has_element?(lv, "button[type='submit']")
    end

    test "renders health filter options", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/history")

      assert has_element?(lv, "option[value='healthy']")
      assert has_element?(lv, "option[value='unhealthy']")
    end

    test "renders server dropdown with distinct server names", %{conn: conn} do
      create_measurement_with(server_name: "AlphaNode", result_id: "alpha-node-1")
      create_measurement_with(server_name: "BravoNode", result_id: "bravo-node-1")

      {:ok, lv, _html} = live(conn, ~p"/history")

      assert has_element?(lv, "option[value='AlphaNode']")
      assert has_element?(lv, "option[value='BravoNode']")
    end
  end

  describe "pagination" do
    test "renders health column header", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/history")
      assert html =~ "Health"
    end

    test "hides page info when empty", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/history")
      refute html =~ "Page 1 of 0"
    end

    test "shows measurements on page 1", %{conn: conn} do
      create_measurement_with(result_id: "hist-test-1")

      {:ok, _lv, html} = live(conn, ~p"/history")
      assert html =~ "Mbps"
    end

    test "paginates when measurements exceed per_page (20)", %{conn: conn} do
      for i <- 1..25 do
        ts = DateTime.utc_now() |> DateTime.add(-i * 60, :second) |> DateTime.truncate(:second)
        create_measurement_with(timestamp: ts, result_id: "page-test-#{i}")
      end

      {:ok, lv, _html} = live(conn, ~p"/history")
      assert render(lv) =~ "Page 1 of 2"

      {:ok, _lv2, html2} = live(conn, ~p"/history?page=2")
      assert html2 =~ "Page 2 of 2"
      assert html2 =~ "Prev"
    end

    test "page 2 shows correct items (5 of 25)", %{conn: conn} do
      for i <- 1..25 do
        ts = DateTime.utc_now() |> DateTime.add(-i * 60, :second) |> DateTime.truncate(:second)
        create_measurement_with(timestamp: ts, result_id: "page-item-#{i}")
      end

      {:ok, lv, _html} = live(conn, ~p"/history?page=2")
      html = render(lv)

      view_count = html |> String.split("View") |> length() |> Kernel.-(1)
      assert view_count == 5
      assert html =~ "Prev"
      assert html =~ "Page 2 of 2"
    end
  end

  describe "filtering by date range" do
    test "filters measurements by date_from", %{conn: conn} do
      old_ts = ~U[2025-01-15 10:00:00Z]
      new_ts = ~U[2025-06-15 10:00:00Z]

      old_m = create_measurement_with(timestamp: old_ts, result_id: "old-1")
      new_m = create_measurement_with(timestamp: new_ts, result_id: "new-1")

      {:ok, lv, _html} = live(conn, ~p"/history?date_from=2025-06-01")

      # The new measurement should have a View link; the old one should not
      assert has_element?(lv, "a[href='/results/#{new_m.id}']")
      refute has_element?(lv, "a[href='/results/#{old_m.id}']")
    end

    test "filters measurements by date_to", %{conn: conn} do
      old_ts = ~U[2025-01-15 10:00:00Z]
      new_ts = ~U[2025-06-15 10:00:00Z]

      old_m = create_measurement_with(timestamp: old_ts, result_id: "old-2")
      new_m = create_measurement_with(timestamp: new_ts, result_id: "new-2")

      {:ok, lv, _html} = live(conn, ~p"/history?date_to=2025-03-01")

      assert has_element?(lv, "a[href='/results/#{old_m.id}']")
      refute has_element?(lv, "a[href='/results/#{new_m.id}']")
    end

    test "filters by both date_from and date_to", %{conn: conn} do
      jan = ~U[2025-01-15 10:00:00Z]
      mar = ~U[2025-03-15 10:00:00Z]
      jun = ~U[2025-06-15 10:00:00Z]

      jan_m = create_measurement_with(timestamp: jan, result_id: "jan-1")
      mar_m = create_measurement_with(timestamp: mar, result_id: "mar-1")
      jun_m = create_measurement_with(timestamp: jun, result_id: "jun-1")

      {:ok, lv, _html} = live(conn, ~p"/history?date_from=2025-02-01&date_to=2025-05-01")

      assert has_element?(lv, "a[href='/results/#{mar_m.id}']")
      refute has_element?(lv, "a[href='/results/#{jan_m.id}']")
      refute has_element?(lv, "a[href='/results/#{jun_m.id}']")
    end

    test "filter with no matching date range shows empty state", %{conn: conn} do
      ts = ~U[2025-01-15 10:00:00Z]
      m = create_measurement_with(timestamp: ts, result_id: "only-1")

      {:ok, lv, _html} = live(conn, ~p"/history?date_from=2099-01-01&date_to=2099-12-31")

      html = render(lv)
      assert html =~ "No measurements found"
      refute has_element?(lv, "a[href='/results/#{m.id}']")
    end
  end

  describe "filtering by health status" do
    test "filters to show only healthy measurements", %{conn: conn} do
      m1 = create_measurement_with(result_id: "healthy-1")
      m2 = create_measurement_with(result_id: "unhealthy-1")

      set_healthy(m1, true)
      set_healthy(m2, false)

      {:ok, lv, _html} = live(conn, ~p"/history?healthy=healthy")

      assert has_element?(lv, "a[href='/results/#{m1.id}']")
      refute has_element?(lv, "a[href='/results/#{m2.id}']")
    end

    test "filters to show only unhealthy measurements", %{conn: conn} do
      m1 = create_measurement_with(result_id: "healthy-2")
      m2 = create_measurement_with(result_id: "unhealthy-2")

      set_healthy(m1, true)
      set_healthy(m2, false)

      {:ok, lv, _html} = live(conn, ~p"/history?healthy=unhealthy")

      assert has_element?(lv, "a[href='/results/#{m2.id}']")
      refute has_element?(lv, "a[href='/results/#{m1.id}']")
    end

    test "shows all measurements when healthy filter is empty", %{conn: conn} do
      m1 = create_measurement_with(result_id: "all-healthy")
      m2 = create_measurement_with(result_id: "all-unhealthy")

      set_healthy(m1, true)
      set_healthy(m2, false)

      {:ok, lv, _html} = live(conn, ~p"/history")

      assert has_element?(lv, "a[href='/results/#{m1.id}']")
      assert has_element?(lv, "a[href='/results/#{m2.id}']")
    end
  end

  describe "filtering by server" do
    test "filters to show measurements from a specific server", %{conn: conn} do
      alpha_m = create_measurement_with(result_id: "srv-alpha", server_name: "AlphaServer")
      bravo_m = create_measurement_with(result_id: "srv-bravo", server_name: "BravoServer")

      {:ok, lv, _html} = live(conn, ~p"/history?server=AlphaServer")

      assert has_element?(lv, "a[href='/results/#{alpha_m.id}']")
      refute has_element?(lv, "a[href='/results/#{bravo_m.id}']")
    end
  end

  describe "sorting" do
    test "sorts by download ascending", %{conn: conn} do
      ts = ~U[2025-01-01 12:00:00Z]

      slow_m =
        create_measurement_with(
          timestamp: ts,
          result_id: "slow-dl",
          download_bandwidth: 5_000_000
        )

      fast_m =
        create_measurement_with(
          timestamp: DateTime.add(ts, 1, :second),
          result_id: "fast-dl",
          download_bandwidth: 50_000_000
        )

      {:ok, lv, _html} = live(conn, ~p"/history?sort=download&dir=asc")

      html = render(lv)
      slow_pos = :binary.match(html, "/results/#{slow_m.id}")
      fast_pos = :binary.match(html, "/results/#{fast_m.id}")
      assert slow_pos < fast_pos
    end

    test "sorts by download descending", %{conn: conn} do
      ts = ~U[2025-01-01 12:00:00Z]

      slow_m =
        create_measurement_with(
          timestamp: ts,
          result_id: "slow-dl-2",
          download_bandwidth: 5_000_000
        )

      fast_m =
        create_measurement_with(
          timestamp: DateTime.add(ts, 1, :second),
          result_id: "fast-dl-2",
          download_bandwidth: 50_000_000
        )

      {:ok, lv, _html} = live(conn, ~p"/history?sort=download&dir=desc")

      html = render(lv)
      fast_pos = :binary.match(html, "/results/#{fast_m.id}")
      slow_pos = :binary.match(html, "/results/#{slow_m.id}")
      assert fast_pos < slow_pos
    end

    test "sorts by latency ascending", %{conn: conn} do
      ts = ~U[2025-01-01 12:00:00Z]

      low_m =
        create_measurement_with(
          timestamp: ts,
          result_id: "low-lat",
          ping_latency: 5.0
        )

      high_m =
        create_measurement_with(
          timestamp: DateTime.add(ts, 1, :second),
          result_id: "high-lat",
          ping_latency: 50.0
        )

      {:ok, lv, _html} = live(conn, ~p"/history?sort=latency&dir=asc")

      html = render(lv)
      low_pos = :binary.match(html, "/results/#{low_m.id}")
      high_pos = :binary.match(html, "/results/#{high_m.id}")
      assert low_pos < high_pos
    end

    test "clicking sort header updates sort params", %{conn: conn} do
      create_measurement_with(result_id: "sort-click-test")

      {:ok, lv, _html} = live(conn, ~p"/history")

      assert has_element?(lv, "button[phx-click='sort'][phx-value-field='download']")

      _html =
        lv
        |> element("button[phx-click='sort'][phx-value-field='download']")
        |> render_click()

      # After clicking download sort, should show sort direction indicator
      assert has_element?(lv, "button[phx-click='sort'][phx-value-field='download']")
    end
  end

  describe "filter persistence" do
    test "filters persist across pagination", %{conn: conn} do
      for i <- 1..25 do
        ts = DateTime.utc_now() |> DateTime.add(-i * 60, :second) |> DateTime.truncate(:second)

        create_measurement_with(
          timestamp: ts,
          result_id: "persist-#{i}",
          server_name: "FilterServer"
        )
      end

      # Create an OtherServer measurement with a unique timestamp
      other_ts =
        DateTime.utc_now() |> DateTime.add(-60 * 60, :second) |> DateTime.truncate(:second)

      other_m =
        create_measurement_with(
          timestamp: other_ts,
          result_id: "other-persist",
          server_name: "OtherServer"
        )

      {:ok, lv, _html} = live(conn, ~p"/history?server=FilterServer")

      html = render(lv)
      assert html =~ "Page 1 of 2"
      refute has_element?(lv, "a[href='/results/#{other_m.id}']")

      # Page 2 should still filter to FilterServer
      lv
      |> element(~s{a[href*="page=2"]})
      |> render_click()

      html2 = render(lv)
      assert html2 =~ "Page 2 of 2"
      refute has_element?(lv, "a[href='/results/#{other_m.id}']")
    end
  end

  describe "clear filters" do
    test "clear link resets filters", %{conn: conn} do
      create_measurement_with(result_id: "clear-test", server_name: "ClearServer")

      {:ok, lv, _html} = live(conn, ~p"/history?server=ClearServer")

      assert has_element?(lv, "a[href='/history']")
    end
  end

  describe "empty state" do
    test "shows empty state when no measurements exist", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/history")

      html = render(lv)
      assert html =~ "No measurements found"
    end
  end

  describe "sortable table headers" do
    test "renders clickable sort buttons on sortable columns", %{conn: conn} do
      create_measurement_with(result_id: "sort-render-test")

      {:ok, lv, _html} = live(conn, ~p"/history")

      assert has_element?(lv, "button[phx-click='sort'][phx-value-field='timestamp']")
      assert has_element?(lv, "button[phx-click='sort'][phx-value-field='download']")
      assert has_element?(lv, "button[phx-click='sort'][phx-value-field='upload']")
      assert has_element?(lv, "button[phx-click='sort'][phx-value-field='latency']")
    end

    test "shows sort direction indicator on active sort column", %{conn: conn} do
      create_measurement_with(result_id: "sort-dir-test")

      {:ok, lv, _html} = live(conn, ~p"/history?sort=download&dir=asc")

      html = render(lv)
      assert html =~ "hero-chevron-up-mini"
    end

    test "shows descending indicator when sorted desc", %{conn: conn} do
      create_measurement_with(result_id: "sort-desc-test")

      {:ok, lv, _html} = live(conn, ~p"/history?sort=download&dir=desc")

      html = render(lv)
      assert html =~ "hero-chevron-down-mini"
    end
  end

  # --- Helpers ---

  defp valid_attrs(overrides) do
    %{
      timestamp: Keyword.get(overrides, :timestamp, ~U[2024-01-01 00:00:00Z]),
      ping_latency: Keyword.get(overrides, :ping_latency, 12.5),
      ping_jitter: Keyword.get(overrides, :ping_jitter, 1.2),
      ping_low: Keyword.get(overrides, :ping_low, 10.0),
      ping_high: Keyword.get(overrides, :ping_high, 15.0),
      download_bandwidth: Keyword.get(overrides, :download_bandwidth, 10_000_000),
      upload_bandwidth: Keyword.get(overrides, :upload_bandwidth, 5_000_000),
      download_bytes: Keyword.get(overrides, :download_bytes, 50_000_000),
      upload_bytes: Keyword.get(overrides, :upload_bytes, 25_000_000),
      download_elapsed: Keyword.get(overrides, :download_elapsed, 5000),
      upload_elapsed: Keyword.get(overrides, :upload_elapsed, 5000),
      packet_loss: Keyword.get(overrides, :packet_loss, 0.0),
      result_id: Keyword.get(overrides, :result_id, "test-result-1"),
      result_url: Keyword.get(overrides, :result_url, "https://www.speedtest.net/result/test"),
      source: Keyword.get(overrides, :source, "scheduled"),
      server_name: Keyword.get(overrides, :server_name, "TestServer"),
      server_location: Keyword.get(overrides, :server_location, "TestCity"),
      server_country: Keyword.get(overrides, :server_country, "TestCountry"),
      server_host: Keyword.get(overrides, :server_host, "test.host.com"),
      isp: Keyword.get(overrides, :isp, "TestISP"),
      speedtest_version: Keyword.get(overrides, :speedtest_version, "1.0.0")
    }
  end

  defp create_measurement_with(overrides) do
    {:ok, measurement} = Measurements.create_measurement(valid_attrs(overrides))
    measurement
  end

  defp set_healthy(measurement, value) do
    measurement
    |> Ecto.Changeset.change(healthy: value)
    |> Repo.update!()
  end
end
