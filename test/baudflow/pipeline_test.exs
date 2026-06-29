defmodule Baudflow.PipelineTest do
  @moduledoc """
  The pinning test for the step-0 event contract. It asserts the whole flow
  fires the expected events end to end - the guard that keeps #13/#21/#22/#23
  additive instead of re-coupling the stages.
  """

  # async: false - mutates the global ntfy env (:ntfy_plug/url/topic) for the
  # NotificationWorker step; serializing avoids racing notification_worker_test
  # over that shared app env.
  use Baudflow.DataCase, async: false
  use Oban.Testing, repo: Baudflow.Repo

  alias Baudflow.Health.HealthWorker
  alias Baudflow.Measurements
  alias Baudflow.Notifications.NotificationWorker
  alias Baudflow.Scheduling
  alias Baudflow.TestRunners.RunnerWorker

  setup do
    Application.put_env(:baudflow, :ntfy_url, "http://ntfy.test")
    Application.put_env(:baudflow, :ntfy_topic, "baudflow-test")
    Application.put_env(:baudflow, :ntfy_plug, {Req.Test, __MODULE__})

    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 200, "") end)

    on_exit(fn ->
      Application.delete_env(:baudflow, :ntfy_url)
      Application.delete_env(:baudflow, :ntfy_topic)
      Application.delete_env(:baudflow, :ntfy_plug)
    end)

    :ok
  end

  test "due_now → runner → measurement → health breach → escalation → notification" do
    # A schedule that fires every minute, with a download threshold the fake
    # speedtest (~51 Mbps) breaches.
    {:ok, schedule} =
      Scheduling.create(%{
        name: "Pin",
        cron: "* * * * *",
        enabled: true,
        threshold_mode: "absolute",
        download: 1000.0
      })

    # 1. Scheduling decides what's due.
    assert [^schedule] = Scheduling.due_now()

    # 2. The dispatcher (SchedulerWorker in 0d) enqueues the runner per schedule.
    %{
      server_id: nil,
      source: "scheduled",
      test_type: schedule.test_type,
      schedule_id: schedule.id
    }
    |> RunnerWorker.new()
    |> Oban.insert()

    # 3. Runner runs the test, inserts a measurement, enqueues HealthWorker.
    [runner_job] = all_enqueued(worker: RunnerWorker)
    assert :ok = perform_job(RunnerWorker, runner_job.args)

    [m] = Measurements.list_recent(limit: 1)
    assert m.test_type == "ookla"
    assert m.schedule_id == schedule.id

    # 4. Health evaluates → breach → atomic streak + escalation + notification.
    # (The verdict itself isn't persisted - it derives JIT - but its effects are.)
    [health_job] = all_enqueued(worker: HealthWorker)
    assert :ok = perform_job(HealthWorker, health_job.args)

    refreshed = Scheduling.get_schedule!(schedule.id)
    assert refreshed.breach_streak == 1
    assert refreshed.escalation_level == 1

    # 5. Notification fires on the breach event.
    [notif_job] = all_enqueued(worker: NotificationWorker)
    assert notif_job.args["kind"] == "breach"
    # The streak is snapshotted into the event args (default threshold 1 → fires).
    assert notif_job.args["streak"] == 1
    assert :ok = perform_job(NotificationWorker, notif_job.args)
  end
end
