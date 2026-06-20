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
          "preferred_servers" => "12345, 67890",
          "blocked_servers" => "54321",
          "retention_days" => "180",
          "dashboard_points" => "200",
          "threshold_enabled" => "true",
          "threshold_download" => "25",
          "threshold_upload" => "10",
          "threshold_ping" => "50"
        }
      })

      assert Settings.get("preferred_servers") == "12345, 67890"
      assert Settings.get("blocked_servers") == "54321"
      assert Settings.get("retention_days") == "180"
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
          "threshold_enabled" => "false"
        }
      })

      html = render(lv)
      assert html =~ "99999"
      assert html =~ "90"
    end
  end
end
