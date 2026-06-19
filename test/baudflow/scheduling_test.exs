defmodule Baudflow.SchedulingTest do
  use Baudflow.DataCase, async: true

  alias Baudflow.Scheduling
  alias Baudflow.Scheduling.Schedule
  alias Baudflow.Settings

  describe "create/1" do
    test "creates a schedule with defaults for a valid cron" do
      assert {:ok, schedule} = Scheduling.create(%{name: "Hourly", cron: "0 * * * *"})

      assert schedule.test_type == "ookla"
      assert schedule.enabled
      assert schedule.escalation_level == 0
      assert schedule.breach_streak == 0
    end

    test "rejects an unparseable cron without raising" do
      assert {:error, changeset} = Scheduling.create(%{name: "Bad", cron: "not a cron"})
      assert "is not a valid cron expression" in errors_on(changeset).cron
    end
  end

  describe "due_now/0" do
    test "returns enabled schedules whose cron matches the current minute" do
      {:ok, _always} = Scheduling.create(%{name: "Always", cron: "* * * * *", enabled: true})

      # a minute guaranteed distinct from "now" (+5, mod 60 — survives roll-over)
      distinct_minute = rem(DateTime.utc_now().minute + 5, 60)

      {:ok, _rare} =
        Scheduling.create(%{name: "Rare", cron: "#{distinct_minute} * * * *", enabled: true})

      due = Enum.map(Scheduling.due_now(), & &1.name)
      assert "Always" in due
      refute "Rare" in due
    end

    test "excludes disabled schedules" do
      {:ok, _} = Scheduling.create(%{name: "Off", cron: "* * * * *", enabled: false})
      due = Enum.map(Scheduling.due_now(), & &1.name)
      refute "Off" in due
    end

    test "skips a schedule with an unparseable cron instead of raising" do
      # bypass changeset validation to plant a bad cron (defensive belt under test)
      {:ok, _} =
        %Schedule{}
        |> Ecto.Changeset.change(%{name: "Bad", cron: "not a cron", enabled: true})
        |> Repo.insert()

      refute Enum.any?(Scheduling.due_now(), &(&1.name == "Bad"))
    end
  end

  describe "escalate/1" do
    test "is an atomic compare-and-set: a stale view cannot double-escalate" do
      {:ok, schedule} = Scheduling.create(%{name: "S", cron: "0 * * * *"})

      # two callers both hold the same stale level-0 view
      stale = Scheduling.get_schedule!(schedule.id)
      assert {:ok, 1} = Scheduling.escalate(stale)
      assert {:ok, 0} = Scheduling.escalate(stale)

      assert Scheduling.get_schedule!(schedule.id).escalation_level == 1
    end
  end

  describe "deescalate/1" do
    test "is a compare-and-set floored at zero" do
      {:ok, schedule} = Scheduling.create(%{name: "S", cron: "0 * * * *"})
      assert schedule.escalation_level == 0

      assert {:ok, 0} = Scheduling.deescalate(schedule)
      assert Scheduling.get_schedule!(schedule.id).escalation_level == 0
    end
  end

  describe "increment_breach_streak/1 and reset_streak/1" do
    test "atomically bumps and clears the streak" do
      {:ok, schedule} = Scheduling.create(%{name: "S", cron: "0 * * * *"})

      assert {:ok, 1} = Scheduling.increment_breach_streak(schedule)
      assert {:ok, 1} = Scheduling.increment_breach_streak(schedule)
      assert Scheduling.get_schedule!(schedule.id).breach_streak == 2

      assert {:ok, 1} = Scheduling.reset_streak(schedule)
      assert Scheduling.get_schedule!(schedule.id).breach_streak == 0
    end
  end

  describe "thresholds_for/1" do
    test "falls back to global settings when the schedule leaves thresholds nil" do
      Settings.update_all(%{
        "threshold_enabled" => "true",
        "threshold_download" => "50",
        "threshold_upload" => "20",
        "threshold_ping" => "5"
      })

      {:ok, schedule} = Scheduling.create(%{name: "S", cron: "0 * * * *"})

      assert Scheduling.thresholds_for(schedule) == %{
               enabled: true,
               download: 50.0,
               upload: 20.0,
               ping: 5.0
             }
    end

    test "a schedule's explicit false overrides a global true (no || trap)" do
      Settings.update_all(%{"threshold_enabled" => "true", "threshold_download" => "50"})

      {:ok, schedule} =
        Scheduling.create(%{
          name: "S",
          cron: "0 * * * *",
          threshold_enabled: false,
          download: 100.0
        })

      thresholds = Scheduling.thresholds_for(schedule)
      refute thresholds.enabled
      assert thresholds.download == 100.0
    end

    test "a schedule's explicit true overrides a global false" do
      # the global default for threshold_enabled is "false"
      {:ok, schedule} =
        Scheduling.create(%{
          name: "S",
          cron: "0 * * * *",
          threshold_enabled: true,
          download: 100.0
        })

      thresholds = Scheduling.thresholds_for(schedule)
      assert thresholds.enabled
      assert thresholds.download == 100.0
    end
  end

  describe "next_run_at/1" do
    test "computes the next fire time for an every-minute schedule" do
      {:ok, schedule} = Scheduling.create(%{name: "S", cron: "* * * * *"})
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      next = Scheduling.next_run_at(schedule)

      assert DateTime.compare(next, now) == :gt
      assert DateTime.diff(next, now, :second) <= 60
    end

    test "returns nil for an unparseable cron" do
      assert nil == Scheduling.next_run_at(%Schedule{cron: "garbage"})
    end
  end

  describe "bootstrap/0" do
    test "seeds a default schedule from the legacy setting, idempotently" do
      Settings.update_all(%{"schedule_cron" => "*/15 * * * *"})

      assert {:ok, _} = Scheduling.bootstrap()

      [only] = Scheduling.list_schedules()
      assert only.cron == "*/15 * * * *"
      assert only.enabled
      assert only.name == "Default"

      assert {:ok, :already_seeded} = Scheduling.bootstrap()
      assert [^only] = Scheduling.list_schedules()
    end

    test "falls back to hourly when the legacy cron is malformed" do
      Settings.update_all(%{"schedule_cron" => "garbage"})

      assert {:ok, _} = Scheduling.bootstrap()

      [only] = Scheduling.list_schedules()
      assert only.cron == "0 * * * *"
    end

    test "does nothing when a schedule already exists" do
      {:ok, existing} = Scheduling.create(%{name: "Mine", cron: "0 0 * * *"})

      assert {:ok, :already_seeded} = Scheduling.bootstrap()
      assert [^existing] = Scheduling.list_schedules()
    end
  end
end
