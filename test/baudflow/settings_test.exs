defmodule Baudflow.SettingsTest do
  use Baudflow.DataCase, async: true

  alias Baudflow.Settings

  describe "update_all/1 + get_all/0 round-trip" do
    test "stores and retrieves settings" do
      assert :ok =
               Settings.update_all(%{
                 "schedule_cron" => "*/5 * * * *",
                 "retention_days" => "30"
               })

      all = Settings.get_all()
      assert all["schedule_cron"] == "*/5 * * * *"
      assert all["retention_days"] == "30"
    end

    test "returns defaults for unset keys" do
      Settings.update_all(%{"schedule_cron" => "0 0 * * *"})

      all = Settings.get_all()
      assert all["schedule_cron"] == "0 0 * * *"
      assert all["server_id"] == ""
      assert all["preferred_servers"] == ""
      assert all["blocked_servers"] == ""
      assert all["retention_days"] == "365"
      assert all["degradation_threshold"] == "0.5"
      assert all["dashboard_points"] == "500"
    end

    test "upserts on repeated calls" do
      Settings.update_all(%{"schedule_cron" => "0 * * * *"})
      Settings.update_all(%{"schedule_cron" => "*/15 * * * *"})

      all = Settings.get_all()
      assert all["schedule_cron"] == "*/15 * * * *"
    end
  end

  describe "get/1" do
    test "returns nil for unknown key" do
      assert Settings.get("nonexistent_key") == nil
    end

    test "returns the value for a stored key" do
      Settings.update_all(%{"server_id" => "12345"})
      assert Settings.get("server_id") == "12345"
    end
  end
end
