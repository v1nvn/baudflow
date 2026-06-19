defmodule Baudflow.Health.HealthWorker do
  @moduledoc """
  Oban worker that evaluates a measurement's health and owns the downstream
  effects: update the measurement, mutate the schedule's breach streak and
  escalation level atomically, enqueue a notification on a transition, and
  broadcast `{:health, id, transition}`.

  This is the only module that constructs an `Event` and the only mutator of
  streak/escalation state (via the `Scheduling` atomic functions).
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  alias Baudflow.Health
  alias Baudflow.Measurements
  alias Baudflow.Measurements.Measurement
  alias Baudflow.Notifications.{Event, NotificationWorker}
  alias Baudflow.Scheduling

  # Transitions that carry enough meaning to reach the notification policy.
  # `:healthy` and still-breaching (nil) never enqueue.
  @notifiable_transitions [:breach, :recovered, :failed]

  @impl true
  def perform(%Oban.Job{args: %{"measurement_id" => id}}) do
    measurement = Measurements.get_measurement!(id)

    case schedule_for(measurement) do
      nil ->
        Logger.warning("no schedule found for measurement #{id}; skipping health evaluation")

      schedule ->
        evaluate_and_mutate(measurement, schedule)
    end

    :ok
  end

  defp evaluate_and_mutate(measurement, schedule) do
    prior_streak = schedule.breach_streak
    {healthy, benchmarks, transition} = Health.evaluate(measurement, schedule)

    case Measurements.update_health(measurement, healthy, benchmarks) do
      {:ok, _updated} ->
        mutate_streak(schedule, healthy, prior_streak)
        escalate_on(transition, schedule)
        notify_on(transition, measurement, schedule)
        broadcast_health(measurement.id, transition)

      {:error, changeset} ->
        Logger.warning(
          "failed to update health for measurement #{measurement.id}: #{inspect(changeset.errors)}"
        )
    end
  end

  # Streak counts consecutive breaches: bump on every unhealthy, reset on the
  # first healthy after a breach run. Atomic via the Scheduling mutators.
  defp mutate_streak(schedule, false, _prior) do
    {:ok, _} = Scheduling.increment_breach_streak(schedule)
  end

  defp mutate_streak(schedule, true, prior) when prior > 0 do
    {:ok, _} = Scheduling.reset_streak(schedule)
  end

  defp mutate_streak(_schedule, _healthy, _prior), do: :ok

  # Escalation level bumps on the breach transition, drops on recovery. Its
  # frequency effect (`escalated_cron`) is wired in #13; step 0 only maintains it.
  defp escalate_on(:breach, schedule) do
    {:ok, _} = Scheduling.escalate(schedule)
  end

  defp escalate_on(:recovered, schedule) do
    {:ok, _} = Scheduling.deescalate(schedule)
  end

  defp escalate_on(_transition, _schedule), do: :ok

  defp notify_on(transition, measurement, schedule) when transition in @notifiable_transitions do
    %Event{kind: transition, measurement_id: measurement.id, schedule_id: schedule.id}
    |> event_to_args()
    |> NotificationWorker.new()
    |> Oban.insert()
  end

  defp notify_on(_transition, _measurement, _schedule), do: :ok

  # Serialize the event to Oban args. Constructed here (the sole Event builder),
  # deserialized via `Event.from_args/1` in the notification worker.
  defp event_to_args(%Event{kind: kind, measurement_id: measurement_id, schedule_id: schedule_id}) do
    %{kind: Atom.to_string(kind), measurement_id: measurement_id, schedule_id: schedule_id}
  end

  defp broadcast_health(_measurement_id, nil), do: :ok

  defp broadcast_health(measurement_id, transition) do
    Phoenix.PubSub.broadcast(
      Baudflow.PubSub,
      "measurements",
      {:health, measurement_id, transition}
    )
  end

  # schedule_id flows from the runner in 0d; until then fall back to the single
  # default schedule (post-bootstrap) so thresholds/streak still resolve.
  defp schedule_for(%Measurement{schedule_id: id}) when is_integer(id) do
    Scheduling.get_schedule!(id)
  end

  defp schedule_for(_measurement) do
    Scheduling.list_schedules() |> List.first()
  end
end
