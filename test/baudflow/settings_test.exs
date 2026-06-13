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

    test "falls back to default when key is not stored" do
      assert Settings.get("schedule_cron") == "0 * * * *"
      assert Settings.get("retention_days") == "365"
      assert Settings.get("dashboard_points") == "500"
    end
  end

  describe "get_integer/2" do
    test "parses a stored integer string" do
      Settings.update_all(%{"retention_days" => "30"})
      assert Settings.get_integer("retention_days") == 30
    end

    test "returns default when key is not stored" do
      # "retention_days" has a default of "365" in @default_settings
      assert Settings.get_integer("retention_days") == 365
    end

    test "returns explicit default for unknown key" do
      assert Settings.get_integer("nonexistent_key", 42) == 42
    end

    test "returns nil for unknown key with no default" do
      assert Settings.get_integer("nonexistent_key") == nil
    end

    test "returns fallback when value is empty string" do
      Settings.update_all(%{"server_id" => ""})
      assert Settings.get_integer("server_id", 0) == 0
    end

    test "returns fallback when value is non-numeric garbage" do
      Settings.update_all(%{"server_id" => "abc"})
      assert Settings.get_integer("server_id", 99) == 99
    end

    test "handles float-looking string by truncating" do
      Settings.update_all(%{"retention_days" => "7.5"})
      assert Settings.get_integer("retention_days", 365) == 7
    end
  end

  describe "get_float/2" do
    test "parses a stored float string" do
      Settings.update_all(%{"degradation_threshold" => "0.75"})
      assert Settings.get_float("degradation_threshold") == 0.75
    end

    test "parses an integer-looking string without crashing" do
      # String.to_float("1") would raise — this must not
      Settings.update_all(%{"degradation_threshold" => "1"})
      assert Settings.get_float("degradation_threshold") == 1.0
    end

    test "parses zero as 0.0" do
      Settings.update_all(%{"degradation_threshold" => "0"})
      assert Settings.get_float("degradation_threshold") == 0.0
    end

    test "returns default when key is not stored" do
      # "degradation_threshold" default is "0.5"
      assert Settings.get_float("degradation_threshold") == 0.5
    end

    test "returns explicit default for unknown key" do
      assert Settings.get_float("nonexistent_key", 3.14) == 3.14
    end

    test "returns nil for unknown key with no default" do
      assert Settings.get_float("nonexistent_key") == nil
    end

    test "returns fallback when value is empty string" do
      Settings.update_all(%{"server_id" => ""})
      assert Settings.get_float("server_id", 0.0) == 0.0
    end

    test "returns fallback when value is non-numeric garbage" do
      Settings.update_all(%{"server_id" => "not-a-number"})
      assert Settings.get_float("server_id", 1.0) == 1.0
    end
  end

  describe "get_boolean/1" do
    test "returns true for 'true'" do
      Settings.update_all(%{"threshold_enabled" => "true"})
      assert Settings.get_boolean("threshold_enabled") == true
    end

    test "returns false for 'false'" do
      Settings.update_all(%{"threshold_enabled" => "false"})
      assert Settings.get_boolean("threshold_enabled") == false
    end

    test "returns false for unknown key (no default)" do
      assert Settings.get_boolean("nonexistent_key") == false
    end

    test "returns false for arbitrary string" do
      Settings.update_all(%{"threshold_enabled" => "yes"})
      assert Settings.get_boolean("threshold_enabled") == false
    end

    test "returns false for empty string" do
      Settings.update_all(%{"threshold_enabled" => ""})
      assert Settings.get_boolean("threshold_enabled") == false
    end

    test "returns false for stored nil (missing key with no default)" do
      assert Settings.get_boolean("nonexistent_key") == false
    end
  end

  describe "get_integer_list/1" do
    test "parses comma-separated integers" do
      Settings.update_all(%{"preferred_servers" => "1, 2, 3"})
      assert Settings.get_integer_list("preferred_servers") == [1, 2, 3]
    end

    test "handles single value" do
      Settings.update_all(%{"preferred_servers" => "42"})
      assert Settings.get_integer_list("preferred_servers") == [42]
    end

    test "returns empty list for empty string" do
      Settings.update_all(%{"preferred_servers" => ""})
      assert Settings.get_integer_list("preferred_servers") == []
    end

    test "returns empty list for nil (missing key)" do
      assert Settings.get_integer_list("nonexistent_key") == []
    end

    test "skips unparseable entries" do
      Settings.update_all(%{"preferred_servers" => "1, abc, 3"})
      assert Settings.get_integer_list("preferred_servers") == [1, 3]
    end

    test "trims whitespace" do
      Settings.update_all(%{"preferred_servers" => "  1 ,  2  ,  3  "})
      assert Settings.get_integer_list("preferred_servers") == [1, 2, 3]
    end

    test "handles trailing comma" do
      Settings.update_all(%{"preferred_servers" => "1,2,"})
      assert Settings.get_integer_list("preferred_servers") == [1, 2]
    end
  end
end
