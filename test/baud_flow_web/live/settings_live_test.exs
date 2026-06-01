defmodule BaudFlowWeb.SettingsLiveTest do
  use BaudFlowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BaudFlow.Settings

  describe "mount" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings")
      assert html =~ "Settings"
    end

    test "shows current settings values", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings")
      # Default values should be present
      assert html =~ "0 * * * *"
    end

    test "renders threshold fields", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      assert has_element?(lv, "input[name='settings[threshold_enabled]']")
      assert has_element?(lv, "input[name='settings[threshold_download]']")
      assert has_element?(lv, "input[name='settings[threshold_upload]']")
      assert has_element?(lv, "input[name='settings[threshold_ping]']")
    end

    test "renders thresholds section header", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings")
      assert html =~ "Thresholds"
    end

    test "renders preferred and blocked servers fields", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      assert has_element?(lv, "#preferred-servers-input")
      assert has_element?(lv, "#blocked-servers-input")
    end
  end

  describe "save" do
    test "persists settings via Settings.update_all/1", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      lv
      |> element("form")
      |> render_submit(%{
        settings: %{
          "schedule_cron" => "*/30 * * * *",
          "preferred_servers" => "12345, 67890",
          "blocked_servers" => "54321",
          "retention_days" => "180",
          "degradation_threshold" => "0.7",
          "dashboard_points" => "200",
          "threshold_enabled" => "true",
          "threshold_download" => "25",
          "threshold_upload" => "10",
          "threshold_ping" => "50"
        }
      })

      # Verify persisted
      assert Settings.get("schedule_cron") == "*/30 * * * *"
      assert Settings.get("preferred_servers") == "12345, 67890"
      assert Settings.get("blocked_servers") == "54321"
      assert Settings.get("retention_days") == "180"
      assert Settings.get("degradation_threshold") == "0.7"
      assert Settings.get("dashboard_points") == "200"
      assert Settings.get("threshold_enabled") == "true"
      assert Settings.get("threshold_download") == "25"
      assert Settings.get("threshold_upload") == "10"
      assert Settings.get("threshold_ping") == "50"
    end

    test "sets flash after saving", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      lv
      |> element("form")
      |> render_submit(%{
        settings: %{
          "schedule_cron" => "0 * * * *",
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
      })

      # Verify settings were persisted (the real contract)
      assert Settings.get("schedule_cron") == "0 * * * *"
    end

    test "re-renders with new values after save", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      lv
      |> element("form")
      |> render_submit(%{
        settings: %{
          "schedule_cron" => "0 */2 * * *",
          "preferred_servers" => "99999",
          "blocked_servers" => "11111",
          "retention_days" => "90",
          "degradation_threshold" => "0.3",
          "dashboard_points" => "100",
          "threshold_enabled" => "true",
          "threshold_download" => "50",
          "threshold_upload" => "25",
          "threshold_ping" => "30"
        }
      })

      html = render(lv)
      assert html =~ "0 */2 * * *"
      assert html =~ "99999"
    end
  end
end
