defmodule Baudflow.TestRunners.Ping do
  @moduledoc """
  TCP-connect latency backend - the second `TestRunner` impl.

  A lightweight, high-frequency reachability/latency check with no bandwidth
  cost: `ping_latency` / `ping_jitter` / `ping_low` / `ping_high` / `packet_loss`
  only. A ping result therefore carries no `download_*` / `upload_*` - those stay
  nil, `from_result/1` skips the mbps derivation, and `Health` skips the
  download/upload checks (a check needs both a threshold and a value).

  Unlike a classic ICMP ping, this opens TCP connections to `host:port` at a
  fixed cadence for the configured run duration and treats each completed
  handshake (~1 RTT) as a latency sample, with failed connects counted as packet
  loss. Sampling for a sustained window (default 10s, via the
  `ping_duration_seconds` setting) averages many readings into a stable
  latency/loss value rather than a noisy burst. TCP needs no external binary and
  no `CAP_NET_RAW` - it works unprivileged under the deployment's locked-down
  `securityContext`, where neither the `ping` binary, `cap_net_raw`, nor the
  `ping_group_range` sysctl is available. The tradeoff is the price of entry: a
  target that doesn't speak TCP on the configured port reads as 100% loss.

  Resolution mirrors `Scheduling.thresholds_for/1`: the schedule's `target_host` /
  `target_port` if present (per-row override), else the global `Settings`
  `ping_target` / `ping_port` (defaults `1.1.1.1` / `443`). `:gen_tcp.connect/4`
  honors its timeout argument strictly, so each attempt is time-bounded and no
  `Task`/`yield` SLA wrapper is needed. Per-sample progress is streamed over
  PubSub as `{:ping_progress, data}` after each connect (mirroring Ookla's
  per-phase stream) so a live view can render samples as they land; the terminal
  `{:result}` still carries the final parsed measurement.
  """

  @behaviour Baudflow.TestRunners.TestRunner

  alias Baudflow.Settings

  # A ping samples at a fixed cadence for a configurable duration, then averages
  # - a longer run smooths transient spikes into a stable latency/loss reading
  # (and SLA verdict) instead of a noisy 5-sample burst.
  @samples_per_second 2
  @cadence_ms div(1000, @samples_per_second)
  @default_duration_seconds 10
  # SLA headroom over the run duration: timeout_ms = duration + grace.
  @grace_seconds 5
  # Per-connect cap = one cadence slot, so a host that blocks to its limit fills
  # the slot instead of stacking (keeps the run ~duration long even if unreachable).
  @connect_timeout_ms @cadence_ms
  # Pacing sleep between samples so the live view renders each as it lands. Zero
  # in :test (config/test.exs) so the suite runs samples back-to-back.
  @sample_interval_ms Application.compile_env(:baudflow, :ping_sample_interval_ms, @cadence_ms)

  @impl true
  def binary_available?, do: true

  @impl true
  # SLA scales with the configured run duration so the safety net never preempts
  # a legitimate long run.
  def timeout_ms, do: duration_seconds() * 1000 + @grace_seconds * 1000

  @impl true
  def run(args) do
    host = args["target_host"] || Settings.get("ping_target")
    port = args["target_port"] || Settings.get_integer("ping_port", 443)
    probe(host, port, args)
  end

  # Run duration (seconds): a per-call arg override (tests), else the global
  # `ping_duration_seconds` setting. One reader, never nil.
  defp duration_seconds(args \\ %{}),
    do:
      args["duration_seconds"] ||
        Settings.get_integer("ping_duration_seconds", @default_duration_seconds)

  defp sample_count(args), do: max(1, duration_seconds(args) * @samples_per_second)

  @impl true
  def parse(%{timings: timings, attempted: attempted, host: host, port: port}) do
    received = length(timings)

    %{
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
      ping_latency: mean(timings),
      ping_jitter: stddev(timings),
      ping_low: lowest(timings),
      ping_high: highest(timings),
      packet_loss: packet_loss(attempted, received),
      raw_result: %{
        "host" => host,
        "port" => port,
        "timings" => timings,
        "attempted" => attempted
      }
    }
  end

  # ── Execution ────────────────────────────────────────────────────

  defp probe(host, port, args) do
    count = sample_count(args)
    start = System.monotonic_time(:millisecond)

    # Collect a latency (ms) for every connect that succeeds; remember the first
    # failure's reason so an all-failed probe can report a stable message. Stream
    # cumulative progress after each attempt so the live view renders samples as
    # they land (mirrors Ookla's per-phase stream - a side-channel only; the
    # final return value is unchanged).
    {timings, error} =
      Enum.reduce(1..count, {[], nil}, fn sample, {acc, err} ->
        pace_to_cadence(sample, start)

        case connect_once(host, port, @connect_timeout_ms) do
          {:ok, ms} ->
            acc = [ms | acc]
            broadcast_progress(progress_payload(sample, count, acc, ms, host, port))
            {acc, err}

          {:error, reason} ->
            broadcast_progress(progress_payload(sample, count, acc, nil, host, port))
            {acc, err || reason}
        end
      end)

    case Enum.reverse(timings) do
      [] -> {:error, "TCP connect failed: #{inspect(error)}"}
      timings -> {:ok, %{timings: timings, attempted: count, host: host, port: port}}
    end
  end

  # Sleep until this sample's cadence boundary so the probe runs for ~duration
  # regardless of per-connect latency: a fast connect sleeps the remainder, a
  # blocking one fills its slot. Skipped entirely in :test (@sample_interval_ms
  # == 0) so samples run back-to-back.
  defp pace_to_cadence(sample, start) do
    if sample > 1 and @sample_interval_ms > 0 do
      target = (sample - 1) * @cadence_ms
      elapsed = System.monotonic_time(:millisecond) - start
      sleep = target - elapsed

      if sleep > 0, do: Process.sleep(sleep)
    end
  end

  # Cumulative per-sample payload for the live view. `timings` is the reversed
  # accumulator (order doesn't matter for mean/stddev), `latency` is this
  # attempt's value or nil when the connect failed.
  defp progress_payload(sample, count, timings, latency, host, port) do
    received = length(timings)

    %{
      sample: sample,
      total: count,
      attempted: sample,
      received: received,
      latency: latency,
      avg: mean(timings),
      jitter: stddev(timings),
      loss: packet_loss(sample, received),
      host: host,
      port: port
    }
  end

  defp broadcast_progress(data) do
    Phoenix.PubSub.broadcast(Baudflow.PubSub, "measurements", {:ping_progress, data})
  end

  # Time the blocking connect directly (it honors its timeout), convert to a
  # float ms once at the end, and always close the socket on success.
  defp connect_once(host, port, timeout) do
    start = System.monotonic_time(:microsecond)

    case :gen_tcp.connect(to_charlist(host), port, connect_opts(), timeout) do
      {:ok, socket} ->
        elapsed_ms = (System.monotonic_time(:microsecond) - start) / 1000.0
        :gen_tcp.close(socket)
        {:ok, elapsed_ms}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp connect_opts, do: [active: false, nodelay: true]

  # ── Statistics ───────────────────────────────────────────────────

  defp mean([]), do: nil

  defp mean(values) do
    Enum.sum(values) / length(values)
  end

  # Population standard deviation: sqrt(sum((x - mean)^2) / n). A single sample
  # has no spread, so its jitter is 0.0; no samples is nil (parse is only ever
  # called on a successful probe, but the guard keeps the helper total).
  defp stddev([]), do: nil
  defp stddev([_]), do: 0.0

  defp stddev(values) do
    count = length(values)
    avg = Enum.sum(values) / count

    sum_sq =
      Enum.reduce(values, 0.0, fn x, acc -> acc + (x - avg) * (x - avg) end)

    :math.sqrt(sum_sq / count)
  end

  defp lowest([]), do: nil
  defp lowest(values), do: Enum.min(values)

  defp highest([]), do: nil
  defp highest(values), do: Enum.max(values)

  # Loss as a 0–100 percent. `attempted == 0` is guarded even though @sample_count
  # is a constant - a malformed call must never divide by zero.
  defp packet_loss(0, _received), do: 0.0

  defp packet_loss(attempted, received) do
    (attempted - received) / attempted * 100.0
  end
end
