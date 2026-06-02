defmodule BaudflowWeb.ResultLiveTest do
  use BaudflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Baudflow.Measurements

  describe "mount" do
    test "renders a measurement's fields", %{conn: conn} do
      {:ok, m} =
        Measurements.create_measurement(
          valid_attrs(
            timestamp: ~U[2024-06-15 12:30:00Z],
            result_id: "result-test-1",
            result_url: "https://www.speedtest.net/result/r1"
          )
        )

      {:ok, _lv, html} = live(conn, ~p"/results/#{m.id}")

      # Check Ookla fields rendered
      assert html =~ "Test Result"
      assert html =~ "80.0"
      assert html =~ "40.0"
      assert html =~ "12.5"
      assert html =~ ~r/1\.2.*ms/s

      # Check speedtest.net link
      assert html =~ "speedtest.net"
    end

    test "renders all Ookla detail fields", %{conn: conn} do
      {:ok, m} =
        Measurements.create_measurement(
          valid_attrs(
            timestamp: ~U[2024-06-15 12:30:00Z],
            result_id: "result-test-2",
            server_name: "MyServer",
            server_location: "MyCity",
            isp: "MyISP",
            source: "manual"
          )
        )

      {:ok, _lv, html} = live(conn, ~p"/results/#{m.id}")

      # Server details
      assert html =~ "MyServer"
      assert html =~ "MyCity"
      assert html =~ "MyISP"
      assert html =~ "manual"
    end

    test "shows back link to history", %{conn: conn} do
      {:ok, m} =
        Measurements.create_measurement(
          valid_attrs(
            timestamp: ~U[2024-06-15 12:30:00Z],
            result_id: "result-test-3"
          )
        )

      {:ok, _lv, html} = live(conn, ~p"/results/#{m.id}")
      assert html =~ "History"
    end

    test "returns 404 for nonexistent measurement", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/results/#{System.unique_integer([:positive])}")
      end
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
end
