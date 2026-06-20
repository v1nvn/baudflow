defmodule Baudflow.TestRunners.Ping do
  @moduledoc """
  ICMP `ping` backend — the second `TestRunner` impl.

  A lightweight, high-frequency latency check with no bandwidth cost:
  `ping_latency` / `ping_jitter` / `ping_low` / `ping_high` / `packet_loss` only.
  A ping result therefore carries no `download_*` / `upload_*` — those stay nil,
  `from_result/1` skips the mbps derivation, and `Health` skips the download/
  upload checks (a check needs both a threshold and a value).

  The target host resolves per-row → global fallback, exactly like
  `Scheduling.thresholds_for/1`: the schedule's `target_host` if set, else the
  global `Settings` `ping_target` (default `1.1.1.1`).

  The binary is resolved at runtime via `Application.get_env(:baudflow,
  :ping_bin)`, falling back to the `PING_BIN` env var, then `"ping"`. Tests point
  this at `test/support/fake_ping`. `System.cmd` runs the count-bounded ping
  inside a `Task` with a `yield`-based SLA, so an unreachable host is killed
  instead of hanging the worker queue. No per-phase progress is streamed — ping
  finishes in a few seconds and the terminal `{:result}` broadcast is enough.
  """

  @behaviour Baudflow.TestRunners.TestRunner

  alias Baudflow.Settings

  # Single source of truth for the SLA: the Task receive window. A count-bounded
  # ping of @packet_count finishes in ~@packet_count seconds against a reachable
  # host; this window absorbs the unreachable-host tail before we kill it.
  @timeout_seconds 15
  @packet_count 5

  @loss_re ~r/(\d+(?:\.\d+)?)% packet loss/

  # Matches both dialects: macOS "round-trip ... stddev" and Linux "rtt ...
  # mdev". Captures: 1 min, 2 avg, 3 max, 4 stddev/mdev.
  @rtt_re ~r/(?:round-trip|rtt)[^=]*=\s*([\d.]+)\/([\d.]+)\/([\d.]+)\/([\d.]+)/

  @impl true
  def binary_available?, do: resolve_path() != nil

  @impl true
  def timeout_ms, do: @timeout_seconds * 1000

  @impl true
  def run(args) do
    host = args["target_host"] || Settings.get("ping_target")

    case resolve_path() do
      nil -> {:error, "ping binary not found: #{ping_bin()}"}
      path -> run_with_timeout(path, host)
    end
  end

  @impl true
  def parse(%{output: output}) do
    %{
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
      ping_latency: capture_float(output, @rtt_re, 2),
      ping_jitter: capture_float(output, @rtt_re, 4),
      ping_low: capture_float(output, @rtt_re, 1),
      ping_high: capture_float(output, @rtt_re, 3),
      packet_loss: capture_float(output, @loss_re, 1),
      raw_result: %{"output" => output}
    }
  end

  # ── Execution ────────────────────────────────────────────────────

  defp run_with_timeout(path, host) do
    task =
      Task.async(fn ->
        System.cmd(path, ["-c", to_string(@packet_count), host], stderr_to_stdout: true)
      end)

    # System.cmd returns {output, exit_status} (a 2-tuple, not ok/error). yield
    # wraps the task's return as {:ok, _}, or {:exit, reason} on a crash, or nil
    # on timeout (then shutdown kills a hung task and returns nil too).
    result = Task.yield(task, timeout_ms()) || Task.shutdown(task, :brutal_kill)

    case result do
      {:ok, {output, 0}} -> {:ok, %{output: output, host: host}}
      {:ok, {output, code}} -> {:error, {:cli_exit, code, output}}
      {:exit, reason} -> {:error, "ping crashed: #{Exception.format_exit(reason)}"}
      nil -> {:error, :timeout}
    end
  end

  defp capture_float(output, regex, index) do
    with [_ | captures] when length(captures) >= index <- Regex.run(regex, output, capture: :all),
         captured <- Enum.at(captures, index - 1),
         {value, _} <- Float.parse(captured) do
      value
    else
      _ -> nil
    end
  end

  # Resolved at RUNTIME so tests can point at a fake script via config. Accepts a
  # bare name ("ping", searched on PATH) or an absolute path (the fake in tests).
  defp ping_bin do
    Application.get_env(:baudflow, :ping_bin) || System.get_env("PING_BIN") || "ping"
  end

  defp resolve_path do
    bin = ping_bin()

    cond do
      File.exists?(bin) -> bin
      path = System.find_executable(bin) -> path
      true -> nil
    end
  end
end
