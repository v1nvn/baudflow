defmodule BaudFlow.Measurements.SpeedtestWorker do
  @moduledoc """
  Oban worker that runs the speedtest CLI, parses the result, inserts a
  measurement, broadcasts on PubSub, and enqueues a notification check.

  The speedtest command is resolved at **runtime** via
  `Application.get_env(:baud_flow, :speedtest_bin)`, falling back to
  `SPEEDTEST_BIN` env var, then `"speedtest"`.  The value may be a bare
  binary name (`"speedtest"`) or a multi-word command
  (`"docker exec baudflow-speedtest speedtest"`). Tests point this at
  `test/support/fake_speedtest`.

  Timeout is enforced by the OS `timeout` coreutil (exit 124), not by
  `System.cmd` (which has no `:timeout` option).
  """
  use Oban.Worker, queue: :speedtest, max_attempts: 2

  alias BaudFlow.Measurements
  alias BaudFlow.Measurements.BenchmarkWorker
  alias BaudFlow.Measurements.NotificationWorker
  alias BaudFlow.Runs

  @doc """
  Returns `true` if the speedtest command is available.

  For a bare binary (`"speedtest"`), checks PATH.
  For a wrapper command (`"docker exec … speedtest"`), checks that the
  first word (e.g. `"docker"`) is in PATH.
  """
  def binary_available? do
    {bin, _prefix} = speedtest_command()
    System.find_executable(bin) != nil
  end

  @impl true
  def perform(%Oban.Job{id: job_id, args: args}) do
    started_at = DateTime.utc_now() |> DateTime.truncate(:second)

    try do
      case run_speedtest(args) do
        {:ok, output} ->
          handle_success(output, args, started_at, job_id)

        {:error, 124, _output} ->
          Runs.fail_run(started_at, "speedtest timed out after 120s", job_id, "timeout")
          {:error, :timeout}

        {:error, exit_code, output} ->
          Runs.fail_run(
            started_at,
            "speedtest CLI exited with code #{exit_code}: #{output}",
            job_id,
            "failure"
          )

          {:error, "speedtest CLI exited with code #{exit_code}"}
      end
    rescue
      e ->
        msg = Exception.message(e)
        broadcast_failure(msg)
        Runs.fail_run(started_at, msg, job_id, "failure")
        {:error, e}
    end
  end

  defp handle_success(output, args, started_at, job_id) do
    case parse_result_line(output) do
      {:ok, result} ->
        attrs =
          result
          |> map_ookla_result()
          |> Map.put(:source, args["source"] || "scheduled")
          |> Map.put(:speedtest_version, System.get_env("SPEEDTEST_VERSION"))

        case Measurements.create_measurement(attrs) do
          {:ok, measurement} ->
            Runs.complete_run(started_at, measurement.id, job_id)

            broadcast_result(measurement)

            %{measurement_id: measurement.id}
            |> NotificationWorker.new()
            |> Oban.insert()

            %{measurement_id: measurement.id}
            |> BenchmarkWorker.new()
            |> Oban.insert()

            :ok

          {:error, changeset} ->
            error = inspect(changeset.errors)
            Runs.fail_run(started_at, error, job_id, "failure")
            broadcast_failure(error)
            {:error, changeset}
        end

      {:error, reason} ->
        Runs.fail_run(started_at, reason, job_id, "failure")
        broadcast_failure(reason)
        {:error, reason}
    end
  end

  @doc """
  Extract the result JSON from speedtest output.

  Handles two formats:
  - Pretty-printed JSON (the whole output is one JSON object)
  - NDJSON with noise (license banners, log lines) - scans for the result line
  """
  def parse_result_line(output) do
    # Try decoding the entire output first (works for pretty-printed JSON)
    case Jason.decode(output) do
      {:ok, %{"type" => "result"} = result} ->
        {:ok, result}

      _ ->
        # Fall back to NDJSON line scanning (handles mixed banner + JSON output)
        case scan_ndjson_for_result(output) do
          nil -> {:error, "no result line found in speedtest output"}
          result -> {:ok, result}
        end
    end
  end

  defp scan_ndjson_for_result(output) do
    output
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case Jason.decode(line) do
        {:ok, %{"type" => "result"} = parsed} -> parsed
        _ -> nil
      end
    end)
  end

  defp broadcast_result(measurement) do
    Phoenix.PubSub.broadcast(
      BaudFlow.PubSub,
      "measurements",
      {:result, measurement}
    )
  end

  defp broadcast_failure(reason) do
    Phoenix.PubSub.broadcast(
      BaudFlow.PubSub,
      "measurements",
      {:test_failed, reason}
    )
  end

  defp run_speedtest(args) do
    cmd = speedtest_cmd(args)

    case System.cmd(cmd.bin, cmd.args, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, output}

      {output, exit_code} ->
        {:error, exit_code, output}
    end
  end

  defp speedtest_cmd(args) do
    server_id = args["server_id"]

    speedtest_args =
      ["--accept-license", "--accept-gdpr", "--format=json"] ++
        if(server_id && server_id != "", do: ["-s", to_string(server_id)], else: [])

    {bin, prefix} = speedtest_command()
    wrapper = timeout_bin()

    all_args = prefix ++ speedtest_args

    if wrapper != nil do
      %{bin: wrapper, args: ["120", bin | all_args]}
    else
      %{bin: bin, args: all_args}
    end
  end

  # Resolved at RUNTIME so tests can point at a fake script via config.
  #
  # Returns `{binary, prefix_args}` where `prefix_args` is [] for a bare
  # binary, or the leading words for a wrapper command like
  # `"docker exec container speedtest"`.
  defp speedtest_command do
    raw =
      Application.get_env(:baud_flow, :speedtest_bin) ||
        System.get_env("SPEEDTEST_BIN") || "speedtest"

    case String.split(raw) do
      [single] -> {single, []}
      [bin | prefix] -> {bin, prefix}
    end
  end

  # Resolve the OS `timeout` coreutil at RUNTIME. Returns nil when
  # unavailable (e.g. macOS) so the worker runs the binary directly.
  defp timeout_bin do
    Application.get_env(:baud_flow, :timeout_bin) ||
      System.get_env("TIMEOUT_BIN") ||
      if(System.find_executable("timeout"), do: "timeout", else: nil)
  end

  defp map_ookla_result(result) do
    %{
      timestamp: parse_timestamp(result["timestamp"]),
      ping_latency: get_in(result, ["ping", "latency"]),
      ping_jitter: get_in(result, ["ping", "jitter"]),
      ping_low: get_in(result, ["ping", "low"]),
      ping_high: get_in(result, ["ping", "high"]),
      download_bandwidth: get_in(result, ["download", "bandwidth"]),
      download_bytes: get_in(result, ["download", "bytes"]),
      download_elapsed: get_in(result, ["download", "elapsed"]),
      download_jitter: get_in(result, ["download", "latency", "jitter"]),
      upload_bandwidth: get_in(result, ["upload", "bandwidth"]),
      upload_bytes: get_in(result, ["upload", "bytes"]),
      upload_elapsed: get_in(result, ["upload", "elapsed"]),
      upload_jitter: get_in(result, ["upload", "latency", "jitter"]),
      packet_loss: result["packetLoss"],
      isp: result["isp"],
      server_id: get_in(result, ["server", "id"]),
      server_name: get_in(result, ["server", "name"]),
      server_location: get_in(result, ["server", "location"]),
      server_country: get_in(result, ["server", "country"]),
      server_host: get_in(result, ["server", "host"]),
      result_id: get_in(result, ["result", "id"]),
      result_url: get_in(result, ["result", "url"]),
      raw_result: result
    }
  end

  defp parse_timestamp(ts) when is_binary(ts) do
    {:ok, datetime, _} = DateTime.from_iso8601(ts)
    datetime
  end
end
