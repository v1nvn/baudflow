defmodule Baudflow.Notifications.WebhookTest do
  # async: false - Req.Test stubs are keyed on the owner ({Req.Test, __MODULE__});
  # a sibling test stubbing the same owner concurrently would clobber this one.
  use Baudflow.DataCase, async: false

  alias Baudflow.Notifications.Webhook
  alias Baudflow.Settings

  setup do
    Application.put_env(:baudflow, :webhook_plug, {Req.Test, __MODULE__})

    on_exit(fn ->
      Application.delete_env(:baudflow, :webhook_plug)
    end)

    :ok
  end

  # Capture the request conn so a test can assert on the posted body.
  defp stub_capture do
    Req.Test.stub(__MODULE__, fn conn ->
      send(self(), {:webhook_request, conn})
      Plug.Conn.send_resp(conn, 200, "")
    end)
  end

  describe "send/1 - enabled (url set)" do
    setup do
      Settings.update_all(%{"webhook_url" => "http://webhook.test/hook"})
      :ok
    end

    test "posts the body to the configured url" do
      stub_capture()

      assert :ok = Webhook.send(~s|{"event":"breach"}|)

      assert_received {:webhook_request, conn}
      body = Req.Test.raw_body(conn)
      assert body =~ ~s|"event"|
    end

    test "does not crash on a non-success status" do
      Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 503, "unavailable") end)

      # A failed POST is a clean :error, never a raise - the worker absorbs it.
      assert :error = Webhook.send(~s|{"event":"breach"}|)
    end
  end

  describe "send/1 - disabled (blank url)" do
    test "is a no-op when no url is configured" do
      stub_capture()

      assert :ok = Webhook.send(~s|{"event":"breach"}|)

      refute_received {:webhook_request, _}
    end
  end
end
