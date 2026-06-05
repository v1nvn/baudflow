defmodule Baudflow.Measurements.SpeedtestWorker do
  @moduledoc """
  Oban worker that runs the speedtest CLI, streams progress events over
  PubSub, parses the final result, inserts a measurement, and enqueues
  notification and benchmark workers.

  The speedtest command is resolved at **runtime** via
  `Application.get_env(:baudflow, :speedtest_bin)`, falling back to
  `SPEEDTEST_BIN` env var, then `"speedtest"`.  The value may be a bare
  binary name (`"speedtest"`) or a multi-word command
  (`"docker exec baudflow-speedtest speedtest"`). Tests point this at
  `test/support/fake_speedtest`.

  Uses `--format=jsonl` (NDJSON) so the CLI streams per-phase progress
  lines (ping, download, upload) that are broadcast on PubSub as
  `{:speedtest_progress, type, data}`.  The final `"type": "result"` line
  is stored as the measurement.

  Timeout is enforced by the OS `timeout` coreutil (exit 124) when
  available, otherwise by a receive timeout on the Port (125 s).
  """
  use Oban.Worker, queue: :speedtest, max_attempts: 2

  alias Baudflow.Measurements
  alias Baudflow.Measurements.BenchmarkWorker
  alias Baudflow.Measurements.NotificationWorker
  alias Baudflow.Runs

  @port_timeout_ms 125_000

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
        {:ok, result} ->
          handle_success(result, args, started_at, job_id)

        {:error, :timeout} ->
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

        {:error, reason} when is_binary(reason) ->
          Runs.fail_run(started_at, reason, job_id, "failure")
          broadcast_failure(reason)
          {:error, reason}
      end
    rescue
      e ->
        msg = Exception.message(e)
        broadcast_failure(msg)
        Runs.fail_run(started_at, msg, job_id, "failure")
        {:error, e}
    end
  end

  defp handle_success(result, args, started_at, job_id) do
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
  end

  # ── Port-based NDJSON streaming ──────────────────────────────────

  defp run_speedtest(args) do
    cmd = speedtest_cmd(args)
    bin_path = System.find_executable(cmd.bin)

    if is_nil(bin_path) do
      {:error, "speedtest binary not found: #{cmd.bin}"}
    else
      port =
        Port.open(
          {:spawn_executable, to_charlist(bin_path)},
          [
            :binary,
            :exit_status,
            :use_stdio,
            {:line, 4096},
            {:args, Enum.map(cmd.args, &to_charlist/1)}
          ]
        )

      stream_output(port, nil, [])
    end
  end

  defp stream_output(port, result, acc) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        new_result = handle_ndjson_line(line, result)
        stream_output(port, new_result, acc)

      {^port, {:exit_status, 0}} ->
        if result do
          {:ok, result}
        else
          {:error, "no result line found in speedtest output"}
        end

      {^port, {:exit_status, 124}} ->
        {:error, :timeout}

      {^port, {:exit_status, code}} ->
        {:error, code, Enum.join(Enum.reverse(acc), "\n")}
    after
      @port_timeout_ms ->
        Port.close(port)
        {:error, :timeout}
    end
  end

  defp handle_ndjson_line(line, result) do
    case Jason.decode(line) do
      {:ok, %{"type" => type} = data} when type in ["testStart", "ping", "download", "upload"] ->
        broadcast_progress(type, data)
        result

      {:ok, %{"type" => "result"} = data} ->
        data

      _ ->
        # Non-JSON line (license banner, blank line, etc.) - skip
        result
    end
  end

  defp broadcast_progress(type, data) do
    Phoenix.PubSub.broadcast(
      Baudflow.PubSub,
      "measurements",
      {:speedtest_progress, type, data}
    )
  end

  # ── PubSub helpers ───────────────────────────────────────────────

  defp broadcast_result(measurement) do
    Phoenix.PubSub.broadcast(
      Baudflow.PubSub,
      "measurements",
      {:result, measurement}
    )
  end

  defp broadcast_failure(reason) do
    Phoenix.PubSub.broadcast(
      Baudflow.PubSub,
      "measurements",
      {:test_failed, reason}
    )
  end

  # ── Command construction ─────────────────────────────────────────

  defp speedtest_cmd(args) do
    server_id = args["server_id"]

    speedtest_args =
      ["--accept-license", "--accept-gdpr", "--format=jsonl"] ++
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
      Application.get_env(:baudflow, :speedtest_bin) ||
        System.get_env("SPEEDTEST_BIN") || "speedtest"

    case String.split(raw) do
      [single] -> {single, []}
      [bin | prefix] -> {bin, prefix}
    end
  end

  # Resolve the OS `timeout` coreutil at RUNTIME. Returns nil when
  # unavailable (e.g. macOS) so the worker runs the binary directly.
  defp timeout_bin do
    Application.get_env(:baudflow, :timeout_bin) ||
      System.get_env("TIMEOUT_BIN") ||
      if(System.find_executable("timeout"), do: "timeout", else: nil)
  end

  # ── Result mapping ───────────────────────────────────────────────

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
