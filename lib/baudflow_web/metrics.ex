defmodule BaudflowWeb.Metrics do
  @moduledoc """
  Renders a `Measurements.metrics/1` snapshot into Prometheus text-exposition
  format for the `/metrics` endpoint. Pure — the controller queries the context,
  this only formats. Every metric is a `baudflow_*` gauge.

  Nil handling: a value that has no current reading (a failed test, or no tests
  yet) renders as `NaN` so Prometheus doesn't carry a stale value. `health` is
  omitted when there's no verdict (calibrating, off mode, failed, or no latest) —
  the verdict itself is derived JIT by `Measurements.metrics/1`, never stored.
  """

  @doc """
  Render a metrics snapshot (`%{latest, total, uptime, health}`) as Prometheus text.
  """
  @spec render(%{
          latest: struct() | nil,
          total: non_neg_integer(),
          uptime: map(),
          health: boolean() | nil
        }) ::
          binary()
  def render(%{latest: latest, total: total, uptime: uptime, health: health}) do
    [
      gauge(
        "baudflow_download_mbps",
        "Latest speed test (Ookla) download speed in Mbps.",
        latest && latest.download_mbps
      ),
      gauge(
        "baudflow_upload_mbps",
        "Latest speed test (Ookla) upload speed in Mbps.",
        latest && latest.upload_mbps
      ),
      gauge(
        "baudflow_ping_latency_ms",
        "Latest speed test latency in milliseconds.",
        latest && latest.ping_latency
      ),
      gauge(
        "baudflow_ping_jitter_ms",
        "Latest speed test jitter in milliseconds.",
        latest && latest.ping_jitter
      ),
      gauge(
        "baudflow_packet_loss",
        "Latest speed test packet loss (raw Ookla value).",
        latest && latest.packet_loss
      ),
      health_metric(health),
      gauge(
        "baudflow_measurements_total",
        "Total number of retained measurements.",
        total
      ),
      gauge(
        "baudflow_uptime_percentage",
        "Percentage of tests over the window that were healthy.",
        uptime && uptime.percent
      )
    ]
    |> IO.iodata_to_binary()
  end

  defp gauge(name, help, value) do
    [
      "# HELP ",
      name,
      " ",
      help,
      "\n",
      "# TYPE ",
      name,
      " gauge\n",
      name,
      " ",
      format_value(value),
      "\n"
    ]
  end

  # nil (no verdict — calibrating, off mode, failed, or no latest) omits the
  # line so Prometheus doesn't carry a stale value.
  defp health_metric(nil), do: []

  defp health_metric(true),
    do: [gauge("baudflow_health", "1 if the latest speed test is healthy, 0 if unhealthy.", 1)]

  defp health_metric(false),
    do: [gauge("baudflow_health", "1 if the latest speed test is healthy, 0 if unhealthy.", 0)]

  defp format_value(nil), do: "NaN"
  defp format_value(value), do: to_string(value)
end
