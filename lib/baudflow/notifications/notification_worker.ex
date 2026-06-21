defmodule Baudflow.Notifications.NotificationWorker do
  @moduledoc """
  Oban worker that runs the four-layer notification pipeline on an event:

      event → policy (notify?) → template (render) → channel (fan out)

  The policy is the pure `Baudflow.Notifications.Policy` module; this worker reads
  `Settings` into the config it hands the policy, then — only when the policy says
  notify — loads the measurement, builds the Payload, and fans out to each channel.
  Rendering is the `Template` module's job (#26): one renderer per channel, so ntfy
  and webhook (#24) add a template, never a parallel render path here. Each channel
  owns its own transport config and enable gate (ntfy via app env; webhook via a
  `Settings` URL — blank means disabled).
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Baudflow.Measurements
  alias Baudflow.Notifications.{Event, Ntfy, Payload, Policy, Template, Webhook}
  alias Baudflow.Settings

  @impl true
  def perform(%Oban.Job{args: args}) do
    event = Event.from_args(args)

    # The policy only reads the event, so decide before paying for the
    # measurement fetch. Most events (healthy, sub-threshold breaches) skip here.
    if Policy.notify?(event, config()) do
      measurement = Measurements.get_measurement!(event.measurement_id)
      %Payload{event: event, measurement: measurement} |> fan_out()
    end

    :ok
  end

  # The streak threshold is the #21 "consecutive breaches before alert" knob.
  # Clamped to >= 1 so a 0/garbage value never silently disables breach alerts.
  defp config do
    %{breach_notify_streak: max(1, Settings.get_integer("breach_notify_streak", 1))}
  end

  # Fan out to every channel — render per channel via the Template layer, then let
  # each channel own its enable gate. ntfy always posts (app env); webhook no-ops
  # when its URL is blank. The worker never branches on channel enable logic.
  defp fan_out(payload) do
    payload |> Template.render(:ntfy) |> Ntfy.send()
    payload |> Template.render(:webhook) |> Webhook.send()

    :ok
  end
end
