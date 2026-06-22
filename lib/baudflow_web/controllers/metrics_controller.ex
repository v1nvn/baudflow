defmodule BaudflowWeb.MetricsController do
  use BaudflowWeb, :controller

  alias Baudflow.Measurements
  alias BaudflowWeb.Metrics

  # Canonical content type for the Prometheus text-exposition format (0.0.4).
  @metrics_content_type "text/plain; version=0.0.4; charset=utf-8"

  @doc """
  Serve the metrics snapshot as Prometheus text. Thin orchestration: the context
  queries, the formatter renders — this only wires the response.
  """
  def index(conn, _params) do
    body = Measurements.metrics() |> Metrics.render()

    conn
    |> put_resp_header("content-type", @metrics_content_type)
    |> send_resp(200, body)
  end
end
