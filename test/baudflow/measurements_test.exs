defmodule Baudflow.MeasurementsTest do
  use Baudflow.DataCase, async: true

  alias Baudflow.Measurements
  alias Baudflow.Measurements.Measurement
  alias Ecto.Adapters.SQL

  # Health verdicts are derived JIT, never stamped. Seed deterministic absolute
  # thresholds so seed_health/2 maps to known verdicts (download >= 50 healthy,
  # < 50 breach, nil → unknown) without touching a stored column.
  setup do
    Baudflow.Settings.update_all(%{"threshold_mode" => "absolute", "threshold_download" => "50"})
    :ok
  end

  describe "from_result/1" do
    test "computes mbps from bandwidth using factor 0.000008" do
      attrs = %{
        timestamp: ~U[2024-01-01 00:00:00Z],
        ping_latency: 12.5,
        download_bandwidth: 10_000_000,
        upload_bandwidth: 5_000_000
      }

      changeset = Measurement.from_result(attrs)
      assert changeset.valid?
      assert changeset.changes[:download_mbps] == 80.0
      assert changeset.changes[:upload_mbps] == 40.0
    end

    test "requires only timestamp" do
      changeset = Measurement.from_result(%{})
      refute changeset.valid?

      errors = Baudflow.DataCase.errors_on(changeset)
      assert "can't be blank" in errors[:timestamp]
      # ping_latency is optional — a failed run carries no ping data, so it must
      # not be required (successful parses always set it).
      refute errors[:ping_latency]
    end

    test "accepts a timestamp-only record (a failed run has no speeds or ping)" do
      changeset = Measurement.from_result(%{timestamp: ~U[2024-01-01 00:00:00Z]})
      assert changeset.valid?
    end

    test "leaves mbps nil when bandwidth is absent (a ping result)" do
      changeset =
        Measurement.from_result(%{timestamp: ~U[2024-01-01 00:00:00Z], ping_latency: 12.5})

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :download_mbps)
      refute Map.has_key?(changeset.changes, :upload_mbps)
    end

    test "dedupes on result_id via unique_constraint" do
      attrs = valid_attrs(result_id: "abc-123")

      assert {:ok, _} = Measurements.create_measurement(attrs)

      assert {:error, changeset} = Measurements.create_measurement(attrs)
      assert "has already been taken" in errors_on(changeset).result_id
    end
  end

  describe "create_measurement/1" do
    test "creates a measurement with valid attributes" do
      attrs = valid_attrs()

      assert {:ok, %Measurement{} = m} = Measurements.create_measurement(attrs)
      assert m.download_mbps == 80.0
      assert m.upload_mbps == 40.0
      assert m.result_id == "test-result-1"
    end
  end

  describe "record_failure/1" do
    test "inserts a failed measurement with nil speeds and failed: true" do
      ts = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:ok, %Measurement{} = m} =
               Measurements.record_failure(%{timestamp: ts, test_type: "ookla"})

      assert m.failed == true
      assert m.timestamp == ts
      assert m.test_type == "ookla"
      # No speed/ping data on a failure — averages and compliance exclude nil.
      assert m.download_mbps == nil
      assert m.upload_mbps == nil
      assert m.ping_latency == nil
    end

    test "defaults test_type to ookla and source to scheduled" do
      assert {:ok, m} =
               Measurements.record_failure(%{timestamp: ~U[2024-01-01 00:00:00Z]})

      assert m.test_type == "ookla"
      assert m.source == "scheduled"
    end

    test "requires a timestamp" do
      assert {:error, changeset} = Measurements.record_failure(%{})
      assert "can't be blank" in errors_on(changeset).timestamp
    end
  end

  describe "update_benchmarks/2" do
    test "persists the benchmarks snapshot and returns {:ok, measurement}" do
      {:ok, m} = Measurements.create_measurement(valid_attrs())

      assert {:ok, updated} =
               Measurements.update_benchmarks(m, %{"download" => %{passed: true}})

      assert updated.benchmarks == %{"download" => %{passed: true}}
    end

    test "accepts nil benchmarks" do
      {:ok, m} = Measurements.create_measurement(valid_attrs())

      assert {:ok, updated} = Measurements.update_benchmarks(m, nil)
      assert updated.benchmarks == nil
    end
  end

  describe "get_measurement!/1" do
    test "returns the measurement with given id" do
      {:ok, m} = Measurements.create_measurement(valid_attrs())
      assert Measurements.get_measurement!(m.id).id == m.id
    end

    test "raises if id does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Measurements.get_measurement!(-1)
      end
    end
  end

  describe "list_recent/1" do
    test "returns measurements newest first" do
      {:ok, _old} =
        Measurements.create_measurement(
          valid_attrs(timestamp: ~U[2024-01-01 00:00:00Z], result_id: "old-1")
        )

      {:ok, _new} =
        Measurements.create_measurement(
          valid_attrs(timestamp: ~U[2024-01-02 00:00:00Z], result_id: "new-1")
        )

      [first, second] = Measurements.list_recent(limit: 10)
      assert first.timestamp > second.timestamp
    end

    test "respects limit" do
      for i <- 1..5 do
        Measurements.create_measurement(
          valid_attrs(
            timestamp: DateTime.add(~U[2024-01-01 00:00:00Z], i * 60, :second),
            result_id: "result-#{i}"
          )
        )
      end

      results = Measurements.list_recent(limit: 3)
      assert length(results) == 3
    end
  end

  describe "list_paginated/1" do
    test "paginates results by page and per_page" do
      for i <- 1..5 do
        Measurements.create_measurement(
          valid_attrs(
            timestamp: DateTime.add(~U[2024-01-01 00:00:00Z], i * 60, :second),
            result_id: "page-result-#{i}"
          )
        )
      end

      page1 = Measurements.list_paginated(page: 1, per_page: 2)
      page2 = Measurements.list_paginated(page: 2, per_page: 2)

      assert length(page1) == 2
      assert length(page2) == 2
      # Different items on each page
      assert Enum.map(page1, & &1.id) != Enum.map(page2, & &1.id)
    end
  end

  describe "count/0" do
    test "returns total count of measurements" do
      Measurements.create_measurement(valid_attrs(result_id: "count-1"))
      Measurements.create_measurement(valid_attrs(result_id: "count-2"))

      assert Measurements.count() == 2
    end
  end

  describe "window_averages/0" do
    test "excludes source == manual" do
      # Non-manual within 7 days
      Measurements.create_measurement(
        valid_attrs(
          timestamp:
            DateTime.add(DateTime.utc_now(), -1 * 3600, :second) |> DateTime.truncate(:second),
          download_bandwidth: 10_000_000,
          source: "scheduled",
          result_id: "wa-scheduled"
        )
      )

      # Manual within 7 days - should be excluded
      Measurements.create_measurement(
        valid_attrs(
          timestamp:
            DateTime.add(DateTime.utc_now(), -1 * 3600, :second) |> DateTime.truncate(:second),
          download_bandwidth: 1_000_000,
          source: "manual",
          result_id: "wa-manual"
        )
      )

      averages = Measurements.window_averages()
      # Only the scheduled one counts (80.0 Mbps)
      assert averages.avg_7d == 80.0
    end

    test "returns nil when no data in window" do
      averages = Measurements.window_averages()
      assert averages.avg_7d == nil
      assert averages.avg_30d == nil
    end

    test "ignores measurements older than the window" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # 10 days old — outside the 7d window, would skew the average if included
      Measurements.create_measurement(
        valid_attrs(
          timestamp: DateTime.add(now, -10 * 24 * 3600, :second),
          download_bandwidth: round(200.0 / 0.000008),
          source: "scheduled",
          result_id: "wa-old"
        )
      )

      Measurements.create_measurement(
        valid_attrs(
          timestamp: DateTime.add(now, -3600, :second),
          download_bandwidth: round(100.0 / 0.000008),
          source: "scheduled",
          result_id: "wa-recent"
        )
      )

      averages = Measurements.window_averages()
      assert_in_delta averages.avg_7d, 100.0, 1.0
    end
  end

  describe "compliance/1" do
    test "returns nil when no promised speed is configured" do
      seed(download_mbps: 500.0)

      assert nil ==
               Measurements.compliance(
                 since: days_ago(7),
                 promised_download: 0.0,
                 promised_upload: 0.0
               )
    end

    test "computes the share of speed tests meeting the download promise" do
      seed(download_mbps: 500.0)
      seed(download_mbps: 100.0)

      result =
        Measurements.compliance(
          since: days_ago(7),
          promised_download: 200.0,
          promised_upload: 0.0
        )

      assert result.meeting == 1
      assert result.total == 2
      assert result.percent == 50.0
    end

    test "a test must meet every configured promise to count" do
      # download passes, upload fails → not compliant
      seed(download_mbps: 500.0, upload_mbps: 10.0)
      # both pass → compliant
      seed(download_mbps: 500.0, upload_mbps: 50.0)

      result =
        Measurements.compliance(
          since: days_ago(7),
          promised_download: 200.0,
          promised_upload: 30.0
        )

      assert result.meeting == 1
      assert result.total == 2
      assert result.percent == 50.0
    end

    test "ignores tests outside the window and ping results (nil download)" do
      seed(download_mbps: 500.0)
      # a ping result carries no download_mbps — never a compliance data point
      {:ok, _} =
        Measurements.create_measurement(%{
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          ping_latency: 5.0,
          result_id: "comp-ping"
        })

      result = Measurements.compliance(since: days_ago(7), promised_download: 200.0)

      assert result.total == 1
      assert result.meeting == 1
    end

    test "returns nil percent when no tests exist in the window (promise still configured)" do
      result = Measurements.compliance(since: days_ago(7), promised_download: 200.0)

      assert result.total == 0
      assert result.percent == nil
    end
  end

  describe "health/1 + health_state/1 (single measurement, absolute mode)" do
    test "maps a measurement to its derived state" do
      healthy = seed_health(~U[2026-06-21 01:00:00Z], true)
      breach = seed_health(~U[2026-06-21 02:00:00Z], false)
      unknown = seed_health(~U[2026-06-21 03:00:00Z], nil)
      {:ok, failed} = Measurements.record_failure(%{timestamp: ~U[2026-06-21 04:00:00Z]})

      assert Measurements.health_state(healthy) == :healthy
      assert Measurements.health_state(breach) == :breach
      assert Measurements.health_state(unknown) == :unknown
      assert Measurements.health_state(failed) == :failed
    end

    test "health/1 returns the per-check benchmarks alongside the state" do
      breach = seed_health(~U[2026-06-21 02:00:00Z], false)

      assert {:breach, %{download: %{passed: false, value: 30.0, unit: "Mbps"}}} =
               Measurements.health(breach)
    end

    test "a failed test is :failed with no benchmarks" do
      {:ok, failed} = Measurements.record_failure(%{timestamp: ~U[2026-06-21 04:00:00Z]})
      assert Measurements.health(failed) == {:failed, nil}
    end
  end

  describe "baseline_for/2 + health_states/1 (auto mode)" do
    setup do
      Baudflow.Settings.update_all(%{"threshold_mode" => "auto", "threshold_ratio" => "0.7"})
      :ok
    end

    test "baseline_for/2 is nil outside auto mode" do
      m = seed(timestamp: ~U[2026-06-21 01:00:00Z], download_mbps: 100.0)
      absolute = %{mode: :absolute, ratio: 0.7, download: 50.0, upload: nil, ping: nil}
      assert Measurements.baseline_for(m, absolute) == nil
    end

    test "baseline_for/2 is :insufficient below the sample floor, a median map above it" do
      auto = Baudflow.Scheduling.global_thresholds()
      at = ~U[2026-06-21 12:00:00Z]

      for i <- 1..11,
          do: seed(timestamp: DateTime.add(at, -i * 3600, :second), download_mbps: 100.0)

      target = seed(timestamp: at, download_mbps: 90.0, result_id: "target")
      assert Measurements.baseline_for(target, auto) == :insufficient

      seed(timestamp: DateTime.add(at, -12 * 3600, :second), download_mbps: 100.0)
      assert %{download: 100.0} = Measurements.baseline_for(target, auto)
    end

    test "health_states/1 matches per-row health_state/1 (point-in-time, per test_type)" do
      base = ~U[2026-06-21 12:00:00Z]

      # 12 ookla baseline samples (median download 100) inside the prior window.
      for i <- 1..12,
          do: seed(timestamp: DateTime.add(base, -i * 3600, :second), download_mbps: 100.0)

      # Targets judged against that baseline: 90 healthy (>= 0.7×100), 60 breach.
      seed(timestamp: base, download_mbps: 90.0, result_id: "auto-healthy")

      seed(
        timestamp: DateTime.add(base, 60, :second),
        download_mbps: 60.0,
        result_id: "auto-breach"
      )

      # A ping row must resolve against the ping baseline, never the ookla one.
      {:ok, _ping} =
        Measurements.create_measurement(%{
          timestamp: base,
          ping_latency: 5.0,
          test_type: "ping",
          result_id: "auto-ping"
        })

      measurements = Measurements.list_recent(limit: 50)
      batch = Measurements.health_states(measurements)

      for m <- measurements do
        assert batch[m.id] == Measurements.health_state(m)
      end

      healthy = Enum.find(measurements, &(&1.result_id == "auto-healthy"))
      breach = Enum.find(measurements, &(&1.result_id == "auto-breach"))
      assert batch[healthy.id] == :healthy
      assert batch[breach.id] == :breach
    end
  end

  describe "health_buckets/1" do
    test "counts per health state within a day bucket" do
      seed_health(~U[2026-06-21 01:00:00Z], true)
      seed_health(~U[2026-06-21 05:00:00Z], true)
      seed_health(~U[2026-06-21 09:00:00Z], false)
      seed_health(~U[2026-06-21 12:00:00Z], nil)
      {:ok, _failed} = Measurements.record_failure(%{timestamp: ~U[2026-06-21 15:00:00Z]})

      [row] =
        Measurements.health_buckets(
          since: ~U[2026-06-20 00:00:00Z],
          test_type: "ookla"
        )

      assert row.total == 5
      assert row.healthy == 2
      assert row.breach == 1
      assert row.failed == 1
      assert row.unknown == 1
    end

    test "returns [] when nothing matches the window" do
      assert Measurements.health_buckets(since: DateTime.utc_now()) == []
    end

    test "test_type filter excludes other runners" do
      {:ok, _ping} =
        Measurements.create_measurement(%{
          timestamp: ~U[2026-06-21 01:00:00Z],
          ping_latency: 5.0,
          test_type: "ping",
          result_id: "hm-ping-1"
        })

      assert Measurements.health_buckets(
               since: ~U[2026-06-20 00:00:00Z],
               test_type: "ookla"
             ) == []
    end

    test "since is optional — nil means full history (the wall grid)" do
      seed_health(~U[2025-01-15 03:00:00Z], true)

      assert length(Measurements.health_buckets(test_type: "ookla")) == 1
    end
  end

  describe "bucket_status/1" do
    test "failed beats breach, healthy, and unknown" do
      assert Measurements.bucket_status(%{failed: 1, breach: 2, healthy: 3, unknown: 4}) ==
               :failed
    end

    test "breach beats healthy and unknown (no failures)" do
      assert Measurements.bucket_status(%{failed: 0, breach: 1, healthy: 3, unknown: 4}) ==
               :breach
    end

    test "healthy beats unknown" do
      assert Measurements.bucket_status(%{failed: 0, breach: 0, healthy: 1, unknown: 2}) ==
               :healthy
    end

    test "only-unknown is :unknown" do
      assert Measurements.bucket_status(%{failed: 0, breach: 0, healthy: 0, unknown: 2}) ==
               :unknown
    end
  end

  describe "daily_health/1" do
    test "returns a Date => status map, worst status wins per day" do
      seed_health(~U[2026-06-21 03:00:00Z], true)
      seed_health(~U[2026-06-21 09:00:00Z], false)

      assert Measurements.daily_health(since: ~U[2026-06-20 00:00:00Z]) ==
               %{~D[2026-06-21] => :breach}
    end

    test "since is optional — omit it to fetch full history" do
      seed_health(~U[2025-01-15 03:00:00Z], true)

      assert Measurements.daily_health() == %{~D[2025-01-15] => :healthy}
    end

    test "scopes to ookla by default (ping excluded)" do
      {:ok, _ping} =
        Measurements.create_measurement(%{
          timestamp: ~U[2026-06-21 01:00:00Z],
          ping_latency: 5.0,
          test_type: "ping",
          result_id: "dh-ping-1"
        })

      assert Measurements.daily_health(since: ~U[2026-06-20 00:00:00Z]) == %{}
    end
  end

  describe "metrics/1" do
    test "returns nil latest and a 0-count snapshot on an empty store" do
      assert %{latest: nil, total: 0, uptime: %{percent: nil, total: 0, healthy: 0}} =
               Measurements.metrics()
    end

    test "latest is the most recent Ookla measurement, ignoring pings" do
      seed(timestamp: days_ago(2), download_mbps: 100.0, result_id: "m-old")

      newest =
        seed(timestamp: days_ago(1), download_mbps: 421.5, result_id: "m-new")

      # A ping an hour newer than the latest speed test must not become latest.
      {:ok, _ping} =
        Measurements.create_measurement(%{
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          ping_latency: 5.0,
          test_type: "ping",
          result_id: "m-ping"
        })

      %{latest: latest, total: 3} = Measurements.metrics()
      assert latest.id == newest.id
      assert latest.download_mbps == 421.5
    end

    test "total counts every retained measurement (all test types)" do
      seed(download_mbps: 100.0, result_id: "m-1")

      {:ok, _ping} =
        Measurements.create_measurement(%{
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          ping_latency: 5.0,
          test_type: "ping",
          result_id: "m-ping"
        })

      assert %{total: 2} = Measurements.metrics()
    end

    test "uptime is the healthy share over the window, excluding older tests" do
      seed_health(days_ago(1), true)
      seed_health(days_ago(1), true)
      seed_health(days_ago(1), false)
      # Outside the 30-day default window — must not count.
      seed_health(days_ago(35), true)

      %{uptime: uptime} = Measurements.metrics()
      assert uptime.healthy == 2
      assert uptime.total == 3
      assert uptime.percent == 66.7
    end

    test "uptime percent is nil when the window has no tests" do
      seed_health(days_ago(35), true)

      assert %{uptime: %{percent: nil, total: 0}} = Measurements.metrics()
    end

    test "a failed test lowers uptime (it counts as non-healthy)" do
      seed_health(days_ago(1), true)
      Measurements.record_failure(%{timestamp: days_ago(1), test_type: "ookla"})

      %{uptime: uptime} = Measurements.metrics()
      assert uptime.healthy == 1
      assert uptime.total == 2
    end
  end

  # --- Migration sanity checks ---

  describe "migration indexes" do
    test "unique index on result_id is present" do
      indexes = indexes_for("measurements")

      assert Enum.any?(indexes, fn idx ->
               idx.columns == ["result_id"] and idx.unique
             end)
    end

    test "GIN index on raw_result is present" do
      indexes = indexes_for("measurements")

      assert Enum.any?(indexes, fn idx ->
               "raw_result" in idx.columns and idx.using == "gin"
             end)
    end
  end

  # --- Helpers ---

  defp valid_attrs(overrides \\ []) do
    %{
      timestamp: Keyword.get(overrides, :timestamp, ~U[2024-01-01 00:00:00Z]),
      ping_latency: Keyword.get(overrides, :ping_latency, 12.5),
      download_bandwidth: Keyword.get(overrides, :download_bandwidth, 10_000_000),
      upload_bandwidth: Keyword.get(overrides, :upload_bandwidth, 5_000_000),
      result_id: Keyword.get(overrides, :result_id, "test-result-1"),
      source: Keyword.get(overrides, :source, "scheduled")
    }
  end

  # Seed a speed test with an explicit mbps (no bandwidth, so from_result keeps
  # the value) and a unique result_id, timestamped "now" unless overridden.
  defp seed(overrides) do
    {:ok, m} =
      Measurements.create_measurement(%{
        timestamp:
          Keyword.get(overrides, :timestamp, DateTime.utc_now() |> DateTime.truncate(:second)),
        ping_latency: Keyword.get(overrides, :ping_latency, 12.5),
        download_mbps: Keyword.get(overrides, :download_mbps),
        upload_mbps: Keyword.get(overrides, :upload_mbps),
        result_id:
          Keyword.get(overrides, :result_id, "comp-#{System.unique_integer([:positive])}"),
        source: Keyword.get(overrides, :source, "scheduled")
      })

    m
  end

  # Seed a speed test at `ts` whose JIT verdict (absolute mode, download
  # threshold 50 from the setup) is the requested state: true → healthy
  # (100 >= 50), false → breach (30 < 50), nil → unknown (no download value,
  # so the check is skipped and no verdict is produced).
  defp seed_health(ts, true), do: seed(timestamp: ts, download_mbps: 100.0)
  defp seed_health(ts, false), do: seed(timestamp: ts, download_mbps: 30.0)
  defp seed_health(ts, nil), do: seed(timestamp: ts, download_mbps: nil)

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days * 24 * 3600, :second)

  defp indexes_for(table) do
    result =
      SQL.query!(
        Baudflow.Repo,
        "SELECT indexname, indexdef FROM pg_indexes WHERE tablename = $1",
        [table]
      )

    Enum.map(result.rows, fn [name, defn] ->
      %{
        name: name,
        columns: extract_columns(defn, table),
        unique: String.contains?(defn, "UNIQUE"),
        using: extract_using(defn)
      }
    end)
  end

  defp extract_columns(defn, table) do
    # Match the column list between parens after the table name
    case Regex.run(~r/#{table}\s+(USING\s+\w+\s+)?\(([^)]+)\)/, defn) do
      [_, _, cols] ->
        cols
        |> String.split(",")
        |> Enum.map(&String.trim/1)

      _ ->
        []
    end
  end

  defp extract_using(defn) do
    case Regex.run(~r/USING\s+(\w+)/, defn) do
      [_, method] -> String.downcase(method)
      _ -> "btree"
    end
  end
end
