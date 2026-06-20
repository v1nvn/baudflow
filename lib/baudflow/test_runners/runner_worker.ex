defmodule Baudflow.TestRunners.RunnerWorker do
  @moduledoc """
  Oban worker that runs a test through its `TestRunner` impl and owns the
  pipeline: insert the measurement, record the run, broadcast the terminal event,
  and enqueue downstream workers.

  The impl is resolved by `test_type` (`"ookla"` today; `"ping"` lands with #15).
  The worker never invokes the test binary directly — that lives in the impl.

  Downstream is a single `HealthWorker` enqueue, which then owns threshold
  evaluation, streak/escalation mutation, and the notification fan-out.
  """

  use Oban.Worker, queue: :speedtest, max_attempts: 2

  alias Baudflow.Health.HealthWorker
  alias Baudflow.Measurements
  alias Baudflow.Runs
  alias Baudflow.TestRunners.Ookla
  alias Baudflow.TestRunners.Ping

  # Single source of truth for runnable impls AND the schedule-form options —
  # add a tuple here and both dispatch and the test_type <select> pick it up.
  @registry [
    {"ookla", "Speedtest (Ookla)", Ookla},
    {"ping", "Ping", Ping}
  ]

  @impls Map.new(@registry, fn {key, _label, mod} -> {key, mod} end)

  @doc "Selectable test types for the schedule form, as {label, value} option tuples."
  def test_types do
    Enum.map(@registry, fn {key, label, _mod} -> {label, key} end)
  end

  @doc "Resolve binary-availability for a test type (dashboard manual run)."
  def binary_available?(test_type \\ "ookla") do
    impl_for(test_type).binary_available?()
  end

  @doc "Resolve the SLA timeout in ms for a test type (dashboard safety net)."
  def timeout_ms(test_type \\ "ookla") do
    impl_for(test_type).timeout_ms()
  end

  @impl true
  def perform(%Oban.Job{id: job_id, args: args}) do
    started_at = DateTime.utc_now() |> DateTime.truncate(:second)
    impl = impl_for(args["test_type"] || "ookla")

    try do
      case impl.run(args) do
        {:ok, result} ->
          handle_success(impl, result, args, started_at, job_id)

        {:error, :timeout} ->
          handle_timeout(impl, started_at, job_id)

        {:error, {:cli_exit, code, output}} ->
          handle_cli_exit(code, output, started_at, job_id)

        {:error, reason} when is_binary(reason) ->
          handle_error(reason, started_at, job_id)
      end
    rescue
      e ->
        msg = Exception.message(e)
        broadcast_failure(msg)
        Runs.fail_run(started_at, msg, job_id, "failure")
        {:error, e}
    end
  end

  defp handle_success(impl, result, args, started_at, job_id) do
    attrs =
      result
      |> impl.parse()
      |> Map.put(:source, args["source"] || "scheduled")
      |> Map.put(:test_type, args["test_type"] || "ookla")
      |> Map.put(:schedule_id, args["schedule_id"])
      |> Map.put(:speedtest_version, System.get_env("SPEEDTEST_VERSION"))

    case Measurements.create_measurement(attrs) do
      {:ok, measurement} ->
        Runs.complete_run(started_at, measurement.id, job_id)
        broadcast_result(measurement)
        enqueue_downstream(measurement.id)
        :ok

      {:error, changeset} ->
        error = inspect(changeset.errors)
        Runs.fail_run(started_at, error, job_id, "failure")
        broadcast_failure(error)
        {:error, changeset}
    end
  end

  defp handle_timeout(impl, started_at, job_id) do
    seconds = div(impl.timeout_ms(), 1000)

    Runs.fail_run(started_at, "speedtest timed out after #{seconds}s", job_id, "timeout")
    broadcast_failure("Timed out after #{seconds}s")
    {:error, :timeout}
  end

  defp handle_cli_exit(code, output, started_at, job_id) do
    Runs.fail_run(
      started_at,
      "speedtest CLI exited with code #{code}: #{output}",
      job_id,
      "failure"
    )

    reason = "Speedtest CLI exited with code #{code}"
    broadcast_failure(reason)
    {:error, reason}
  end

  defp handle_error(reason, started_at, job_id) do
    Runs.fail_run(started_at, reason, job_id, "failure")
    broadcast_failure(reason)
    {:error, reason}
  end

  defp enqueue_downstream(measurement_id) do
    %{measurement_id: measurement_id}
    |> HealthWorker.new()
    |> Oban.insert()
  end

  defp broadcast_result(measurement) do
    Phoenix.PubSub.broadcast(Baudflow.PubSub, "measurements", {:result, measurement})
  end

  defp broadcast_failure(reason) do
    Phoenix.PubSub.broadcast(Baudflow.PubSub, "measurements", {:test_failed, reason})
  end

  defp impl_for(test_type), do: Map.fetch!(@impls, test_type)
end
