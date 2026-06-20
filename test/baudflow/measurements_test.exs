defmodule Baudflow.MeasurementsTest do
  use Baudflow.DataCase, async: true

  alias Baudflow.Measurements
  alias Baudflow.Measurements.Measurement
  alias Ecto.Adapters.SQL

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

    test "requires only timestamp and ping_latency" do
      changeset = Measurement.from_result(%{})
      refute changeset.valid?

      errors = Baudflow.DataCase.errors_on(changeset)
      assert "can't be blank" in errors[:timestamp]
      assert "can't be blank" in errors[:ping_latency]
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

  describe "update_health/3" do
    test "updates healthy and benchmarks and returns {:ok, measurement}" do
      {:ok, m} = Measurements.create_measurement(valid_attrs())

      assert {:ok, updated} =
               Measurements.update_health(m, true, %{"download" => %{passed: true}})

      assert updated.healthy == true
      assert updated.benchmarks == %{"download" => %{passed: true}}
    end

    test "accepts nil healthy and benchmarks" do
      {:ok, m} = Measurements.create_measurement(valid_attrs())

      assert {:ok, updated} = Measurements.update_health(m, nil, nil)
      assert updated.healthy == nil
      assert updated.benchmarks == nil
    end

    test "returns {:error, changeset} rather than raising on an invalid healthy value" do
      {:ok, m} = Measurements.create_measurement(valid_attrs())

      assert {:error, changeset} = Measurements.update_health(m, "not-a-boolean", nil)
      assert "is invalid" in errors_on(changeset).healthy
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
