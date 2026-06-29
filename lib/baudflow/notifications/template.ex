defmodule Baudflow.Notifications.Template do
  @moduledoc """
  The template layer of the four-stage notification pipeline: renders a
  `Baudflow.Notifications.Payload` into a channel-specific message string.

  One renderer for every channel (ntfy today, webhook in #24) - a new channel adds a
  default template + an override slot, never a parallel render path in the worker.
  Templates are EEx strings: webhook's is user-editable via `Settings` (#26, blank =
  built-in default); ntfy's is a fixed default that reproduces the pre-#26 message
  (its output is pinned by `notification_worker_test.exs`). A render error (a bad
  custom template) logs and falls back to the channel default - a bad setting never
  crashes the `:notifications` queue.
  """

  require Logger

  alias Baudflow.Measurements.Measurement
  alias Baudflow.Notifications.Payload
  alias Baudflow.Settings

  @channels [:ntfy, :webhook]

  @ntfy_default """
  <%= case @event.kind do %>
  <% :breach -> %>Speed threshold breached!

  <%= @failed_checks.(@measurement) %>Server: <%= @measurement.server_name %> (<%= @measurement.server_location %>)
  <% :recovered -> %>Speed recovered.

  Thresholds are back in spec.
  Server: <%= @measurement.server_name %> (<%= @measurement.server_location %>)
  <% :failed -> %>Speed test failed.

  The most recent test produced no result.
  <% end %>
  """

  @webhook_default ~s|{"event":<%= @json.(@event.kind) %>,"streak":<%= @json.(@event.streak) %>,"schedule_id":<%= @json.(@event.schedule_id) %>,"measurement":{"download_mbps":<%= @json.(@measurement.download_mbps) %>,"upload_mbps":<%= @json.(@measurement.upload_mbps) %>,"ping_latency_ms":<%= @json.(@measurement.ping_latency) %>,"packet_loss":<%= @json.(@measurement.packet_loss) %>,"server":<%= @json.(@measurement.server_name) %>,"server_location":<%= @json.(@measurement.server_location) %>,"failed":<%= @json.(@measurement.failed) %>,"timestamp":<%= @json.(@measurement.timestamp) %>,"result_url":<%= @json.(@measurement.result_url) %>}}|

  @defaults %{ntfy: @ntfy_default, webhook: @webhook_default}

  @type channel :: :ntfy | :webhook

  @doc "Resolve the template (Settings override or default) and render the payload."
  @spec render(Payload.t(), channel()) :: String.t()
  def render(%Payload{} = payload, channel) when channel in @channels do
    render_string(payload, channel, template_for(channel))
  end

  @doc """
  Render an explicit template string against the payload.

  Pure - the test seam. `render/2` resolves the template then delegates here. Falls
  back to the channel default on any error, so a malformed custom template degrades
  instead of raising.
  """
  @spec render_string(Payload.t(), channel(), String.t()) :: String.t()
  def render_string(%Payload{} = payload, channel, template) when channel in @channels do
    eval(template, payload)
  rescue
    e ->
      Logger.warning(
        "notification template render failed for #{channel}: #{Exception.message(e)}"
      )

      eval(default(channel), payload)
  end

  @doc "The built-in default template string for a channel (also the UI placeholder)."
  @spec default(channel()) :: String.t()
  def default(channel), do: Map.fetch!(@defaults, channel)

  # ntfy: fixed default (not user-tunable). webhook: a stored override wins, blank/nil
  # falls back to the built-in default - one "unset" representation (nil/"" both mean
  # default), matching the escalated_cron / promised_* idioms.
  defp template_for(:ntfy), do: @ntfy_default

  defp template_for(:webhook) do
    case Settings.get("webhook_template") do
      s when is_binary(s) and s != "" -> s
      _ -> @webhook_default
    end
  end

  defp eval(template, payload) do
    EEx.eval_string(template, assigns: assigns(payload), trim: true)
  end

  # Bind data + captured helpers. @json.(v) JSON-encodes a value (nil -> null); the
  # webhook default uses it so server names with quotes never break the payload.
  # @failed_checks.(m) is the moved breach formatter; the ntfy default uses it.
  defp assigns(%Payload{event: event, measurement: measurement}) do
    %{
      event: event,
      measurement: measurement,
      json: &json/1,
      failed_checks: &failed_checks/1
    }
  end

  defp json(value), do: Jason.encode!(value)

  # benchmarks is JSONB → string keys after the DB round-trip. Moved verbatim from
  # NotificationWorker (the pre-#26 render); the ntfy default template calls it with
  # the measurement so it reads as "the failed checks for this measurement."
  defp failed_checks(%Measurement{benchmarks: benchmarks}) when is_map(benchmarks) do
    benchmarks
    |> Enum.filter(fn
      {_, %{"passed" => p}} -> not p
      _ -> false
    end)
    |> Enum.map_join("", fn {metric, %{"value" => v, "threshold" => t, "unit" => u}} ->
      "#{String.capitalize(to_string(metric))}: #{fmt(v)} vs #{fmt(t)} #{u}\n"
    end)
  end

  defp failed_checks(_), do: ""

  defp fmt(n) when is_number(n), do: Float.round(n / 1, 1)
  defp fmt(_), do: "?"
end
