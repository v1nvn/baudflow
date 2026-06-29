defmodule Baudflow.Notifications.TemplateTest do
  # Pure - no DB. Builds structs in memory and renders through the pure seam
  # (render_string/3); the Settings resolution in render/2 is exercised end-to-end
  # by notification_worker_test.exs.
  use ExUnit.Case, async: true

  alias Baudflow.Measurements.Measurement
  alias Baudflow.Notifications.{Event, Payload, Template}

  @ts ~U[2026-06-21 12:00:00Z]

  defp payload(kind, measurement_overrides \\ %{}) do
    measurement = struct!(Measurement, Map.merge(measurement_defaults(), measurement_overrides))

    %Payload{
      event: %Event{kind: kind, measurement_id: 1, schedule_id: 1, streak: 1},
      measurement: measurement
    }
  end

  defp measurement_defaults do
    %{
      timestamp: @ts,
      download_mbps: 421.0,
      upload_mbps: 100.0,
      ping_latency: 12.0,
      packet_loss: 0.0,
      server_name: "TestServer",
      server_location: "TestCity",
      result_url: "https://speedtest/r/123",
      failed: false
    }
  end

  describe "ntfy default template" do
    test "breach lists the failed check and the server" do
      msg =
        Template.render_string(
          payload(:breach, %{benchmarks: breach_benchmarks()}),
          :ntfy,
          Template.default(:ntfy)
        )

      assert msg =~ "breached"
      assert msg =~ "Download"
      assert msg =~ "TestServer"
    end

    test "recovered names the server" do
      msg = Template.render_string(payload(:recovered), :ntfy, Template.default(:ntfy))

      assert msg =~ "recover"
      assert msg =~ "TestServer"
    end

    test "failed renders the outage without crashing on nil server fields" do
      msg =
        Template.render_string(
          payload(:failed, %{server_name: nil, server_location: nil}),
          :ntfy,
          Template.default(:ntfy)
        )

      assert msg =~ "fail"
    end
  end

  describe "webhook default template" do
    test "renders valid JSON with the event kind and measurement" do
      msg = Template.render_string(payload(:breach), :webhook, Template.default(:webhook))

      assert {:ok, decoded} = Jason.decode(msg)
      assert decoded["event"] == "breach"
      assert decoded["streak"] == 1
      assert decoded["schedule_id"] == 1
      assert decoded["measurement"]["download_mbps"] == 421.0
      assert decoded["measurement"]["upload_mbps"] == 100.0
      assert decoded["measurement"]["server"] == "TestServer"
      assert decoded["measurement"]["failed"] == false
    end

    test "encodes nils as JSON null (a failed/ping measurement)" do
      msg =
        Template.render_string(
          payload(:failed, %{download_mbps: nil, upload_mbps: nil}),
          :webhook,
          Template.default(:webhook)
        )

      assert {:ok, decoded} = Jason.decode(msg)
      assert decoded["event"] == "failed"
      assert decoded["measurement"]["download_mbps"] == nil
    end
  end

  describe "custom template" do
    test "renders a user-supplied EEx string" do
      msg =
        Template.render_string(
          payload(:breach),
          :webhook,
          "event=<%= @event.kind %> dl=<%= @measurement.download_mbps %>"
        )

      assert msg =~ "event=breach"
      assert msg =~ "dl=421.0"
    end
  end

  describe "bad template falls back to the default" do
    test "a render error degrades to the channel default instead of raising" do
      msg =
        Template.render_string(
          payload(:breach),
          :webhook,
          "<%= @measurement.nonexistent %>"
        )

      # Fell back to the default JSON, not a raise.
      assert {:ok, decoded} = Jason.decode(msg)
      assert decoded["event"] == "breach"
    end
  end

  defp breach_benchmarks do
    %{"download" => %{"passed" => false, "value" => 50.0, "threshold" => 100.0, "unit" => "Mbps"}}
  end
end
