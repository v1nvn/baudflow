defmodule Baudflow.Notifications.NotificationWorkerTest do
  # async: false — the capture test's Req.Test stub can be clobbered by a
  # sibling test stubbing the same owner ({Req.Test, __MODULE__}) concurrently.
  # Serializing keeps the stub-per-test deterministic.
  use Baudflow.DataCase, async: false
  use Oban.Testing, repo: Baudflow.Repo

  alias Baudflow.Measurements
  alias Baudflow.Notifications.NotificationWorker
  alias Baudflow.Settings

  setup do
    Application.put_env(:baudflow, :ntfy_url, "http://ntfy.test")
    Application.put_env(:baudflow, :ntfy_topic, "baudflow-test")
    Application.put_env(:baudflow, :ntfy_plug, {Req.Test, __MODULE__})

    on_exit(fn ->
      Application.delete_env(:baudflow, :ntfy_url)
      Application.delete_env(:baudflow, :ntfy_topic)
      Application.delete_env(:baudflow, :ntfy_plug)
    end)

    :ok
  end

  defp stub_success do
    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 200, "") end)
  end

  # Capture the request conn so a test can assert on the rendered body. Both
  # channels POST through the same Req.Test owner ({Req.Test, __MODULE__}); tag by
  # host so a test can tell a webhook POST (webhook.test) from an ntfy POST.
  defp stub_capture do
    Req.Test.stub(__MODULE__, fn conn ->
      send(self(), {request_tag(conn), conn})
      Plug.Conn.send_resp(conn, 200, "")
    end)
  end

  defp request_tag(%Plug.Conn{host: "webhook.test"}), do: :webhook_request
  defp request_tag(_conn), do: :ntfy_request

  defp insert_measurement!(overrides) do
    defaults = %{
      timestamp: DateTime.utc_now(),
      ping_latency: 10.0,
      download_bandwidth: round(50.0 / 0.000008),
      upload_bandwidth: round(25.0 / 0.000008),
      server_name: "TestServer",
      server_location: "TestCity",
      source: "scheduled",
      result_id: Ecto.UUID.generate()
    }

    {:ok, m} = Measurements.create_measurement(Map.merge(defaults, overrides))
    m
  end

  describe "perform/1 - breach" do
    test "posts an alert to ntfy" do
      stub_success()

      m = insert_measurement!(%{benchmarks: breach_benchmarks()})

      assert :ok =
               perform_job(NotificationWorker, %{
                 "kind" => "breach",
                 "measurement_id" => m.id,
                 "streak" => 1
               })
    end

    test "does not crash when ntfy returns an error status" do
      Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 503, "unavailable") end)

      m = insert_measurement!(%{benchmarks: breach_benchmarks()})

      assert :ok =
               perform_job(NotificationWorker, %{
                 "kind" => "breach",
                 "measurement_id" => m.id,
                 "streak" => 1
               })
    end

    test "renders the failed threshold in the body" do
      stub_capture()

      m = insert_measurement!(%{benchmarks: breach_benchmarks()})

      assert :ok =
               perform_job(NotificationWorker, %{
                 "kind" => "breach",
                 "measurement_id" => m.id,
                 "streak" => 1
               })

      assert_received {:ntfy_request, conn}
      body = Req.Test.raw_body(conn)
      assert body =~ "breached"
      assert body =~ "Download"
    end
  end

  describe "perform/1 - recovery (#22)" do
    # Recovery notifies now. stub_capture messages self() on the POST so we can
    # assert it actually fired — Ntfy swallows Req.Test errors, so a bare :ok
    # never proves anything.
    test "posts an alert to ntfy" do
      stub_capture()

      m = insert_measurement!(%{})

      assert :ok =
               perform_job(NotificationWorker, %{
                 "kind" => "recovered",
                 "measurement_id" => m.id
               })

      assert_received {:ntfy_request, conn}
      body = Req.Test.raw_body(conn)
      assert body =~ "recover"
    end
  end

  describe "perform/1 - failure (#23)" do
    test "posts an alert to ntfy" do
      stub_capture()

      m = insert_measurement!(%{failed: true})

      assert :ok =
               perform_job(NotificationWorker, %{
                 "kind" => "failed",
                 "measurement_id" => m.id
               })

      assert_received {:ntfy_request, conn}
      body = Req.Test.raw_body(conn)
      assert body =~ "fail"
    end
  end

  describe "perform/1 - policy" do
    # No notify means no POST — stub_capture messages self() only on a real POST,
    # so refute_received is a reliable assertion (Ntfy swallows Req.Test errors,
    # so an unstubbed wrongful POST would NOT raise — we can't rely on that).

    test "does not notify on a healthy event" do
      stub_capture()
      m = insert_measurement!(%{})

      assert :ok =
               perform_job(NotificationWorker, %{
                 "kind" => "healthy",
                 "measurement_id" => m.id
               })

      refute_received {:ntfy_request, _}
    end

    test "respects the consecutive-breach streak threshold (#21)" do
      Settings.update_all(%{"breach_notify_streak" => "3"})

      stub_capture()
      m = insert_measurement!(%{benchmarks: breach_benchmarks()})

      # streak 1 < threshold 3 → no notify.
      assert :ok =
               perform_job(NotificationWorker, %{
                 "kind" => "breach",
                 "measurement_id" => m.id,
                 "streak" => 1
               })

      refute_received {:ntfy_request, _}

      # streak 3 == threshold → notify.
      assert :ok =
               perform_job(NotificationWorker, %{
                 "kind" => "breach",
                 "measurement_id" => m.id,
                 "streak" => 3
               })

      assert_received {:ntfy_request, _}

      # streak 4 > threshold → no re-notify (reduce alert fatigue).
      assert :ok =
               perform_job(NotificationWorker, %{
                 "kind" => "breach",
                 "measurement_id" => m.id,
                 "streak" => 4
               })

      refute_received {:ntfy_request, _}
    end
  end

  describe "perform/1 - webhook channel (#24)" do
    # webhook_plug routes the webhook POST through the same Req.Test owner as ntfy;
    # the webhook_url setting is per-test (enabled vs disabled).
    setup do
      Application.put_env(:baudflow, :webhook_plug, {Req.Test, __MODULE__})

      on_exit(fn ->
        Application.delete_env(:baudflow, :webhook_plug)
      end)

      :ok
    end

    test "posts an alert to the webhook when a url is configured" do
      Settings.update_all(%{"webhook_url" => "http://webhook.test/hook"})
      stub_capture()

      m = insert_measurement!(%{benchmarks: breach_benchmarks()})

      assert :ok =
               perform_job(NotificationWorker, %{
                 "kind" => "breach",
                 "measurement_id" => m.id,
                 "streak" => 1
               })

      assert_received {:webhook_request, conn}
      body = Req.Test.raw_body(conn)
      assert body =~ ~s|"event"|
      assert body =~ "breach"
    end

    test "does not post to the webhook when no url is configured" do
      stub_capture()

      m = insert_measurement!(%{benchmarks: breach_benchmarks()})

      assert :ok =
               perform_job(NotificationWorker, %{
                 "kind" => "breach",
                 "measurement_id" => m.id,
                 "streak" => 1
               })

      # ntfy still fires (no regression); webhook stays silent with a blank URL.
      assert_received {:ntfy_request, _}
      refute_received {:webhook_request, _}
    end
  end

  defp breach_benchmarks do
    %{
      "download" => %{"passed" => false, "value" => 50.0, "threshold" => 100.0, "unit" => "Mbps"}
    }
  end
end
