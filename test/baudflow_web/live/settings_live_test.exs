defmodule BaudflowWeb.SettingsLiveTest do
  use BaudflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Baudflow.Settings

  describe "mount" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings")
      assert html =~ "Settings"
    end

    test "links to the schedules management page", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/settings")
      assert has_element?(lv, "#manage-schedules-link[href='/schedules']")
      assert html =~ "Manage schedules"
    end

    test "renders threshold fields", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      assert has_element?(lv, "select[name='settings[threshold_mode]']")
      assert has_element?(lv, "input[name='settings[threshold_ratio]']")
      assert has_element?(lv, "input[name='settings[threshold_download]']")
      assert has_element?(lv, "input[name='settings[threshold_upload]']")
      assert has_element?(lv, "input[name='settings[threshold_ping]']")
    end

    test "renders thresholds section header", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings")
      assert html =~ "Thresholds"
    end

    test "renders the ping target and port fields", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      assert has_element?(lv, "#ping-target-input")
      assert has_element?(lv, "#ping-port-input")
      assert has_element?(lv, "input[name='settings[ping_port]']")
    end

    test "renders preferred and blocked servers fields", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      assert has_element?(lv, "#preferred-servers-input")
      assert has_element?(lv, "#blocked-servers-input")
    end

    test "renders promised-speed (SLA) fields", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/settings")

      assert has_element?(lv, "#promised-download-input")
      assert has_element?(lv, "#promised-upload-input")
      assert has_element?(lv, "input[name='settings[promised_download_mbps]']")
      assert has_element?(lv, "input[name='settings[promised_upload_mbps]']")
      assert html =~ "Promised"
    end

    test "renders the consecutive-breach alert field (#21)", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/settings")

      assert has_element?(lv, "#breach-notify-streak-input")
      assert has_element?(lv, "input[name='settings[breach_notify_streak]']")
      assert html =~ "Consecutive"
    end

    test "renders the webhook fields (#24, #26)", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/settings")

      assert has_element?(lv, "#webhook-url-input")
      assert has_element?(lv, "input[name='settings[webhook_url]']")
      assert has_element?(lv, "#webhook-template-input")
      assert has_element?(lv, "textarea[name='settings[webhook_template]']")
      assert html =~ "Webhooks"
    end
  end

  describe "save" do
    test "persists settings via Settings.update_all/1", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      lv
      |> element("form")
      |> render_submit(%{
        settings: %{
          "preferred_servers" => "12345, 67890",
          "blocked_servers" => "54321",
          "retention_days" => "180",
          "dashboard_points" => "200",
          "threshold_mode" => "absolute",
          "threshold_ratio" => "0.8",
          "threshold_download" => "25",
          "threshold_upload" => "10",
          "threshold_ping" => "50",
          "promised_download_mbps" => "500",
          "promised_upload_mbps" => "100",
          "breach_notify_streak" => "3",
          "webhook_url" => "https://example.com/hook",
          "webhook_template" => "{\"event\":\"<%= @event.kind %>\"}"
        }
      })

      assert Settings.get("preferred_servers") == "12345, 67890"
      assert Settings.get("blocked_servers") == "54321"
      assert Settings.get("retention_days") == "180"
      assert Settings.get("dashboard_points") == "200"
      assert Settings.get("threshold_mode") == "absolute"
      assert Settings.get("threshold_ratio") == "0.8"
      assert Settings.get("threshold_download") == "25"
      assert Settings.get("threshold_upload") == "10"
      assert Settings.get("threshold_ping") == "50"
      assert Settings.get("promised_download_mbps") == "500"
      assert Settings.get("promised_upload_mbps") == "100"
      assert Settings.get("breach_notify_streak") == "3"
      assert Settings.get("webhook_url") == "https://example.com/hook"
      assert Settings.get("webhook_template") == "{\"event\":\"<%= @event.kind %>\"}"
    end

    test "sets flash after saving", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      lv
      |> element("form")
      |> render_submit(%{settings: %{"retention_days" => "365"}})

      assert render(lv) =~ "Settings saved"
    end

    test "re-renders with new values after save", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      lv
      |> element("form")
      |> render_submit(%{
        settings: %{
          "preferred_servers" => "99999",
          "blocked_servers" => "11111",
          "retention_days" => "90",
          "dashboard_points" => "100",
          "threshold_mode" => "off"
        }
      })

      html = render(lv)
      assert html =~ "99999"
      assert html =~ "90"
    end
  end
end
