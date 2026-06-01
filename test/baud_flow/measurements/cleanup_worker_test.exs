defmodule BaudFlow.Measurements.CleanupWorkerTest do
  use BaudFlow.DataCase, async: true
  use Oban.Testing, repo: BaudFlow.Repo

  alias BaudFlow.Measurements
  alias BaudFlow.Measurements.CleanupWorker
  alias BaudFlow.Settings

  setup do
    # Seed a known retention window so the cutoff is deterministic.
    Settings.update_all(%{"retention_days" => "7"})

    :ok
  end

  defp insert_measurement!(attrs) do
    # Build defaults for required fields, merge caller overrides.
    defaults = %{
      timestamp: DateTime.utc_now(),
      ping_latency: 10.0,
      download_bandwidth: 1_000_000,
      upload_bandwidth: 500_000,
      result_id: Ecto.UUID.generate()
    }

    {:ok, m} = Measurements.create_measurement(Map.merge(defaults, attrs))
    m
  end

  describe "perform/1" do
    test "deletes measurements older than retention_days" do
      now = DateTime.utc_now()
      # 10 days ago - beyond the 7-day retention window
      old_ts = DateTime.add(now, -10 * 24 * 3600, :second)

      insert_measurement!(%{timestamp: old_ts, result_id: "old-1"})

      assert Measurements.count() == 1

      assert {:ok, pruned: 1} = perform_job(CleanupWorker, %{})

      assert Measurements.count() == 0
    end

    test "keeps measurements within the retention window" do
      now = DateTime.utc_now()
      # 3 days ago - inside the 7-day window
      recent_ts = DateTime.add(now, -3 * 24 * 3600, :second)

      insert_measurement!(%{timestamp: recent_ts, result_id: "recent-1"})

      assert {:ok, pruned: 0} = perform_job(CleanupWorker, %{})

      assert Measurements.count() == 1
    end

    test "retention boundary: exactly at cutoff is kept" do
      # retention_days = 7, so cutoff = now - 7*86400
      # A measurement at exactly cutoff is NOT less than cutoff, so it stays.
      now = DateTime.utc_now()
      boundary_ts = DateTime.add(now, -7 * 24 * 3600, :second)

      insert_measurement!(%{timestamp: boundary_ts, result_id: "boundary-1"})

      assert {:ok, pruned: 0} = perform_job(CleanupWorker, %{})

      assert Measurements.count() == 1
    end

    test "prunes only old rows, keeps recent ones" do
      now = DateTime.utc_now()

      # Two old, two recent
      insert_measurement!(%{
        timestamp: DateTime.add(now, -10 * 24 * 3600, :second),
        result_id: "old-1"
      })

      insert_measurement!(%{
        timestamp: DateTime.add(now, -9 * 24 * 3600, :second),
        result_id: "old-2"
      })

      insert_measurement!(%{
        timestamp: DateTime.add(now, -1 * 24 * 3600, :second),
        result_id: "recent-1"
      })

      insert_measurement!(%{
        timestamp: DateTime.add(now, -2 * 24 * 3600, :second),
        result_id: "recent-2"
      })

      assert {:ok, pruned: 2} = perform_job(CleanupWorker, %{})
      assert Measurements.count() == 2
    end
  end
end
