defmodule Baudflow.SchedulingTest do
  use Baudflow.DataCase, async: true

  alias Baudflow.Measurements
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

    test "accepts a valid escalated cron and normalizes blank to nil" do
      assert {:ok, schedule} =
               Scheduling.create(%{
                 name: "Hourly",
                 cron: "0 * * * *",
                 escalated_cron: "*/5 * * * *"
               })

      assert schedule.escalated_cron == "*/5 * * * *"

      assert {:ok, cleared} =
               Scheduling.create(%{name: "Other", cron: "0 * * * *", escalated_cron: ""})

      assert cleared.escalated_cron == nil
    end

    test "rejects an unparseable escalated cron without raising" do
      assert {:error, changeset} =
               Scheduling.create(%{name: "Bad", cron: "0 * * * *", escalated_cron: "nope"})

      assert "is not a valid cron expression" in errors_on(changeset).escalated_cron
    end
  end

  describe "delete/1" do
    test "removes the schedule" do
      {:ok, schedule} = Scheduling.create(%{name: "Gone", cron: "0 * * * *"})
      assert {:ok, %Schedule{}} = Scheduling.delete(schedule)
      refute Enum.any?(Scheduling.list_schedules(), &(&1.id == schedule.id))
    end

    test "nilifies schedule_id on linked measurements (FK on_delete)" do
      {:ok, schedule} = Scheduling.create(%{name: "Gone", cron: "0 * * * *"})

      {:ok, measurement} =
        Measurements.create_measurement(%{
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          ping_latency: 5.0,
          download_bandwidth: 1000,
          upload_bandwidth: 500,
          schedule_id: schedule.id
        })

      assert {:ok, _} = Scheduling.delete(schedule)
      assert Measurements.get_measurement!(measurement.id).schedule_id == nil
    end
  end

  describe "due_now/0" do
    test "returns enabled schedules whose cron matches the current minute" do
      # Pinned instant (minute 30): "Always" matches every minute, "Rare" fires
      # on minute 15 and so is not due at this instant.
      now = ~U[2026-03-15 10:30:42Z]

      {:ok, _always} = Scheduling.create(%{name: "Always", cron: "* * * * *", enabled: true})
      {:ok, _rare} = Scheduling.create(%{name: "Rare", cron: "15 * * * *", enabled: true})

      due = Enum.map(Scheduling.due_now(now), & &1.name)
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
    test "atomically bumps and clears the streak, returning the resulting value" do
      {:ok, schedule} = Scheduling.create(%{name: "S", cron: "0 * * * *"})

      # The mutators return the streak value they just wrote (read atomically via
      # `returning:`), not a row-count - so HealthWorker can snapshot it into the
      # breach event without a racy second read.
      assert {:ok, 1} = Scheduling.increment_breach_streak(schedule)
      assert {:ok, 2} = Scheduling.increment_breach_streak(schedule)
      assert {:ok, 3} = Scheduling.increment_breach_streak(schedule)
      assert Scheduling.get_schedule!(schedule.id).breach_streak == 3

      assert {:ok, 0} = Scheduling.reset_streak(schedule)
      assert Scheduling.get_schedule!(schedule.id).breach_streak == 0
    end
  end

  describe "thresholds_for/1" do
    test "falls back to global settings when the schedule leaves thresholds nil" do
      Settings.update_all(%{
        "threshold_mode" => "auto",
        "threshold_ratio" => "0.8",
        "threshold_download" => "50",
        "threshold_upload" => "20",
        "threshold_ping" => "5"
      })

      {:ok, schedule} = Scheduling.create(%{name: "S", cron: "0 * * * *"})

      # ratio is only resolved in :auto (the mode that uses it); here it falls
      # back to the configured 0.8.
      assert Scheduling.thresholds_for(schedule) == %{
               mode: :auto,
               ratio: 0.8,
               download: 50.0,
               upload: 20.0,
               ping: 5.0
             }
    end

    test "a schedule's explicit mode overrides a global setting (no || trap)" do
      Settings.update_all(%{"threshold_mode" => "absolute", "threshold_download" => "50"})

      {:ok, schedule} =
        Scheduling.create(%{
          name: "S",
          cron: "0 * * * *",
          threshold_mode: "off",
          download: 100.0
        })

      thresholds = Scheduling.thresholds_for(schedule)
      assert thresholds.mode == :off
      assert thresholds.download == 100.0
    end

    test "defaults to :auto with ratio 0.7 when nothing is configured" do
      {:ok, schedule} = Scheduling.create(%{name: "S", cron: "0 * * * *"})

      thresholds = Scheduling.thresholds_for(schedule)
      assert thresholds.mode == :auto
      assert thresholds.ratio == 0.7
    end
  end

  describe "next_run_at/1" do
    test "computes the next fire time for an every-minute schedule" do
      {:ok, schedule} = Scheduling.create(%{name: "S", cron: "* * * * *"})

      assert Scheduling.next_run_at(schedule, ~U[2026-03-15 10:30:42Z]) ==
               ~U[2026-03-15 10:31:00Z]
    end

    test "returns nil for an unparseable cron" do
      assert nil == Scheduling.next_run_at(%Schedule{cron: "garbage"})
    end
  end

  describe "next_run/0" do
    test "returns the soonest next fire across enabled schedules" do
      {:ok, _hourly} = Scheduling.create(%{name: "Hourly", cron: "0 * * * *"})
      {:ok, _minutely} = Scheduling.create(%{name: "Minutely", cron: "* * * * *"})

      # Pin the instant: at 10:30:42 the minutely schedule next fires at 10:31:00
      # and the hourly at 11:00:00, so the minutely is the unambiguous winner.
      # Reading the wall clock here made this flaky - in minute :59 both fire at
      # the top of the next hour (a genuine tie with no well-defined winner).
      assert %{name: "Minutely", at: ~U[2026-03-15 10:31:00Z]} =
               Scheduling.next_run(~U[2026-03-15 10:30:42Z])
    end

    test "ignores disabled schedules" do
      {:ok, _off} = Scheduling.create(%{name: "Off", cron: "* * * * *", enabled: false})
      assert nil == Scheduling.next_run()
    end

    test "returns nil when no enabled schedules exist" do
      assert nil == Scheduling.next_run()
    end
  end

  describe "adaptive cadence (#13)" do
    test "active_cron/1 returns the base cron when not escalated" do
      {:ok, schedule} =
        Scheduling.create(%{name: "S", cron: "0 * * * *", escalated_cron: "* * * * *"})

      # escalation_level defaults to 0 → base cadence, even with an escalated cron set.
      assert Scheduling.active_cron(schedule) == "0 * * * *"
    end

    test "active_cron/1 returns the escalated cron when escalated" do
      {:ok, schedule} =
        Scheduling.create(%{name: "S", cron: "0 * * * *", escalated_cron: "*/2 * * * *"})

      {:ok, 1} = Scheduling.escalate(schedule)
      escalated = Scheduling.get_schedule!(schedule.id)

      assert Scheduling.active_cron(escalated) == "*/2 * * * *"
    end

    test "active_cron/1 falls back to the base cron when escalated but no escalated cron is set" do
      {:ok, schedule} = Scheduling.create(%{name: "S", cron: "0 * * * *"})
      {:ok, 1} = Scheduling.escalate(schedule)
      escalated = Scheduling.get_schedule!(schedule.id)

      # escalation_level is maintained but inert without a configured speedup.
      assert Scheduling.active_cron(escalated) == "0 * * * *"
    end

    test "due_now/0 fires on the escalated cron while a schedule is escalated" do
      # Pinned instant (minute 30): base cron (minute 15) does NOT match, so the
      # schedule is not due until it escalates to the every-minute cadence.
      now = ~U[2026-03-15 10:30:42Z]

      {:ok, schedule} =
        Scheduling.create(%{
          name: "Escalatable",
          cron: "15 * * * *",
          escalated_cron: "* * * * *",
          enabled: true
        })

      refute "Escalatable" in Enum.map(Scheduling.due_now(now), & &1.name)

      {:ok, 1} = Scheduling.escalate(schedule)

      # Escalated to minutely → now due even though the base (hourly) cron isn't.
      assert "Escalatable" in Enum.map(Scheduling.due_now(now), & &1.name)
    end

    test "next_run_at/2 reflects the escalated cadence while escalated" do
      {:ok, schedule} =
        Scheduling.create(%{name: "S", cron: "0 * * * *", escalated_cron: "* * * * *"})

      {:ok, 1} = Scheduling.escalate(schedule)
      escalated = Scheduling.get_schedule!(schedule.id)

      # Minutely cadence fires at the next minute boundary, not up to an hour out.
      assert Scheduling.next_run_at(escalated, ~U[2026-03-15 10:30:42Z]) ==
               ~U[2026-03-15 10:31:00Z]
    end
  end

  describe "bootstrap/0" do
    test "seeds an Ookla and a Ping schedule from the legacy cron, idempotently" do
      Settings.update_all(%{"schedule_cron" => "*/15 * * * *"})

      assert :ok = Scheduling.bootstrap()

      schedules = Scheduling.list_schedules()
      assert Enum.map(schedules, & &1.test_type) |> Enum.sort() == ["ookla", "ping"]

      [ookla] = for(s <- schedules, s.test_type == "ookla", do: s)
      assert ookla.cron == "*/15 * * * *"
      assert ookla.escalated_cron == "*/15 * * *"
      assert ookla.enabled
      assert ookla.name == "Default"

      [ping] = for(s <- schedules, s.test_type == "ping", do: s)
      assert ping.cron == "*/15 * * * *"
      assert ping.escalated_cron == "*/15 * * *"
      assert ping.name == "Ping"

      # Idempotent - re-bootstrap doesn't duplicate either kind.
      assert :ok = Scheduling.bootstrap()
      assert length(Scheduling.list_schedules()) == 2
    end

    test "falls back to hourly when the legacy cron is malformed" do
      Settings.update_all(%{"schedule_cron" => "garbage"})

      assert :ok = Scheduling.bootstrap()

      [ookla] = for(s <- Scheduling.list_schedules(), s.test_type == "ookla", do: s)
      assert ookla.cron == "0 * * * *"
    end

    test "seeds only the missing test_type, leaving a custom schedule untouched" do
      # A user with a custom Ookla schedule gains a Ping on next boot; their
      # Ookla schedule is never replaced.
      {:ok, mine} = Scheduling.create(%{name: "Mine", cron: "0 0 * * *", test_type: "ookla"})

      assert :ok = Scheduling.bootstrap()

      schedules = Scheduling.list_schedules()
      assert Enum.map(schedules, & &1.test_type) |> Enum.sort() == ["ookla", "ping"]
      assert Enum.any?(schedules, &(&1.id == mine.id))
    end
  end
end
