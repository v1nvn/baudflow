defmodule Baudflow.Measurements.BenchmarkWorkerTest do
  use Baudflow.DataCase, async: true
  use Oban.Testing, repo: Baudflow.Repo

  alias Baudflow.Measurements
  alias Baudflow.Measurements.BenchmarkWorker
  alias Baudflow.Settings

  setup do
    Application.put_env(:baudflow, :ntfy_url, "http://127.0.0.1:1")
    Application.put_env(:baudflow, :ntfy_topic, "baudflow-test")

    on_exit(fn ->
      Application.delete_env(:baudflow, :ntfy_url)
      Application.delete_env(:baudflow, :ntfy_topic)
    end)

    :ok
  end

  defp insert_measurement!(attrs) do
    defaults = %{
      timestamp: DateTime.utc_now(),
      ping_latency: 10.0,
      download_bandwidth: round(50.0 / 0.000008),
      upload_bandwidth: round(25.0 / 0.000008),
      server_name: "TestServer",
      server_location: "TestCity",
      source: "scheduled",
      result_id: Ecto.UUID.generate()
    }

    {:ok, m} = Measurements.create_measurement(Map.merge(defaults, attrs))
    m
  end

  describe "perform/1 - threshold disabled" do
    test "skips when threshold_enabled is false" do
      Settings.update_all(%{
        "threshold_enabled" => "false",
        "threshold_download" => "25",
        "threshold_upload" => "10",
        "threshold_ping" => "50"
      })

      m = insert_measurement!(%{})

      assert :ok = perform_job(BenchmarkWorker, %{"measurement_id" => m.id})

      reloaded = Measurements.get_measurement!(m.id)
      assert reloaded.healthy == nil
      assert reloaded.benchmarks == nil
    end
  end

  describe "perform/1 - all thresholds pass" do
    test "marks healthy when all thresholds pass" do
      Settings.update_all(%{
        "threshold_enabled" => "true",
        "threshold_download" => "25",
        "threshold_upload" => "10",
        "threshold_ping" => "50"
      })

      # download_mbps = 50.0, upload_mbps = 25.0, ping_latency = 10.0
      m = insert_measurement!(%{})

      assert :ok = perform_job(BenchmarkWorker, %{"measurement_id" => m.id})

      reloaded = Measurements.get_measurement!(m.id)
      assert reloaded.healthy == true
      assert reloaded.benchmarks["download"]["passed"] == true
      assert reloaded.benchmarks["upload"]["passed"] == true
      assert reloaded.benchmarks["ping"]["passed"] == true
    end
  end

  describe "perform/1 - threshold failures" do
    test "marks unhealthy when download below threshold" do
      Settings.update_all(%{
        "threshold_enabled" => "true",
        "threshold_download" => "100",
        "threshold_upload" => "0",
        "threshold_ping" => "0"
      })

      # download_mbps = 50.0, which is < 100
      m = insert_measurement!(%{})

      assert :ok = perform_job(BenchmarkWorker, %{"measurement_id" => m.id})

      reloaded = Measurements.get_measurement!(m.id)
      assert reloaded.healthy == false
      assert reloaded.benchmarks["download"]["passed"] == false
      assert reloaded.benchmarks["download"]["threshold"] == 100.0
    end

    test "marks unhealthy when ping above threshold" do
      Settings.update_all(%{
        "threshold_enabled" => "true",
        "threshold_download" => "0",
        "threshold_upload" => "0",
        "threshold_ping" => "5"
      })

      # ping_latency = 10.0, which is > 5
      m = insert_measurement!(%{})

      assert :ok = perform_job(BenchmarkWorker, %{"measurement_id" => m.id})

      reloaded = Measurements.get_measurement!(m.id)
      assert reloaded.healthy == false
      assert reloaded.benchmarks["ping"]["passed"] == false
      assert reloaded.benchmarks["ping"]["threshold"] == 5.0
    end
  end

  describe "perform/1 - disabled thresholds" do
    test "sets healthy to nil when no thresholds configured (all zero)" do
      Settings.update_all(%{
        "threshold_enabled" => "true",
        "threshold_download" => "0",
        "threshold_upload" => "0",
        "threshold_ping" => "0"
      })

      m = insert_measurement!(%{})

      assert :ok = perform_job(BenchmarkWorker, %{"measurement_id" => m.id})

      reloaded = Measurements.get_measurement!(m.id)
      assert reloaded.healthy == nil
      assert reloaded.benchmarks == nil
    end

    test "marks healthy when only some thresholds set and they all pass" do
      Settings.update_all(%{
        "threshold_enabled" => "true",
        "threshold_download" => "25",
        "threshold_upload" => "0",
        "threshold_ping" => "0"
      })

      # download_mbps = 50.0 >= 25.0
      m = insert_measurement!(%{})

      assert :ok = perform_job(BenchmarkWorker, %{"measurement_id" => m.id})

      reloaded = Measurements.get_measurement!(m.id)
      assert reloaded.healthy == true
      assert Map.has_key?(reloaded.benchmarks, "download")
      refute Map.has_key?(reloaded.benchmarks, "upload")
      refute Map.has_key?(reloaded.benchmarks, "ping")
    end
  end
end
