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
    if measurement.failed do
      # A failed test carries no values to threshold — it's its own signal. Emit
      # a :failed event without evaluating thresholds, mutating streak/escalation
      # (a CLI failure is neither a confirmed breach nor a recovery), or
      # broadcasting :health (the runner already broadcast {:result, _} for the
      # UI). This keeps Event construction inside Health.
      emit_event(:failed, measurement, schedule, nil)
    else
      evaluate_thresholds(measurement, schedule)
    end
  end

  defp evaluate_thresholds(measurement, schedule) do
    prior_streak = schedule.breach_streak
    {healthy, benchmarks, transition} = Health.evaluate(measurement, schedule)

    case Measurements.update_health(measurement, healthy, benchmarks) do
      {:ok, _updated} ->
        new_streak = mutate_streak(schedule, healthy, prior_streak)
        escalate_on(transition, schedule)
        maybe_emit(healthy, transition, measurement, schedule, new_streak)
        broadcast_health(measurement.id, transition)

      {:error, changeset} ->
        Logger.warning(
          "failed to update health for measurement #{measurement.id}: #{inspect(changeset.errors)}"
        )
    end
  end

  # Streak counts consecutive breaches: bump on every unhealthy (returning the
  # new streak so it can be snapshotted into the event), reset on the first
  # healthy after a breach run. Atomic via the Scheduling mutators.
  defp mutate_streak(schedule, false, _prior) do
    {:ok, new_streak} = Scheduling.increment_breach_streak(schedule)
    new_streak
  end

  defp mutate_streak(schedule, true, prior) when prior > 0 do
    {:ok, _} = Scheduling.reset_streak(schedule)
    0
  end

  defp mutate_streak(_schedule, _healthy, _prior), do: nil

  # Escalation level bumps on the breach transition, drops on recovery. Its
  # frequency effect (`escalated_cron`) is wired in #13; step 0 only maintains it.
  defp escalate_on(:breach, schedule) do
    {:ok, _} = Scheduling.escalate(schedule)
  end

  defp escalate_on(:recovered, schedule) do
    {:ok, _} = Scheduling.deescalate(schedule)
  end

  defp escalate_on(_transition, _schedule), do: :ok

  # A breach event fires on EVERY unhealthy result (carrying the streak just
  # written) so the notification policy can gate on the climbing streak (#21);
  # recovery fires once on the :recovered transition (#22). :healthy, the
  # thresholds-off nil, and the steady-healthy case emit nothing.
  defp maybe_emit(false, _transition, measurement, schedule, streak) do
    emit_event(:breach, measurement, schedule, streak)
  end

  defp maybe_emit(true, :recovered, measurement, schedule, _streak) do
    emit_event(:recovered, measurement, schedule, nil)
  end

  defp maybe_emit(_healthy, _transition, _measurement, _schedule, _streak), do: :ok

  defp emit_event(kind, measurement, schedule, streak) do
    %Event{kind: kind, measurement_id: measurement.id, schedule_id: schedule.id, streak: streak}
    |> event_to_args()
    |> NotificationWorker.new()
    |> Oban.insert()
  end

  # Serialize the event to Oban args. Constructed here (the sole Event builder),
  # deserialized via `Event.from_args/1` in the notification worker.
  defp event_to_args(%Event{
         kind: kind,
         measurement_id: measurement_id,
         schedule_id: schedule_id,
         streak: streak
       }) do
    %{
      kind: Atom.to_string(kind),
      measurement_id: measurement_id,
      schedule_id: schedule_id,
      streak: streak
    }
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
