defmodule Baudflow.TestRunners.PingTest do
  # The Ping runner resolves its run duration through Settings (DB-backed), so
  # these run on DataCase. parse/1 stays pure; run/1 is pointed at an explicit
  # target_host/target_port plus a short `duration_seconds` arg override so the
  # tests sample a handful of times instead of the full default 10s.
  use Baudflow.DataCase, async: true

  import Baudflow.Test.TcpListener

  alias Baudflow.TestRunners.Ping

  # 2s × 2 samples/sec = 4 samples - enough to exercise averaging/streaming fast.
  @short %{"duration_seconds" => 2}

  describe "parse/1" do
    test "derives latency/low/high/jitter/packet_loss from timings" do
      attrs =
        Ping.parse(%{timings: [10.0, 12.0], attempted: 5, host: "1.1.1.1", port: 443})

      assert attrs.ping_latency == 11.0
      assert attrs.ping_low == 10.0
      assert attrs.ping_high == 12.0
      assert attrs.ping_jitter == 1.0
      assert attrs.packet_loss == 60.0
      assert %DateTime{} = attrs.timestamp
      assert attrs.raw_result["timings"] == [10.0, 12.0]
      assert attrs.raw_result["attempted"] == 5
      assert attrs.raw_result["host"] == "1.1.1.1"
      assert attrs.raw_result["port"] == 443
    end

    test "zero jitter and zero loss when all samples equal and received" do
      attrs = Ping.parse(%{timings: [10.0, 10.0, 10.0], attempted: 3, host: "h", port: 443})

      assert attrs.ping_latency == 10.0
      assert attrs.ping_low == 10.0
      assert attrs.ping_high == 10.0
      assert attrs.ping_jitter == 0.0
      assert attrs.packet_loss == 0.0
    end

    test "single sample has zero jitter and counts the rest as loss" do
      attrs = Ping.parse(%{timings: [15.0], attempted: 5, host: "h", port: 443})

      assert attrs.ping_latency == 15.0
      assert attrs.ping_low == 15.0
      assert attrs.ping_high == 15.0
      assert attrs.ping_jitter == 0.0
      assert attrs.packet_loss == 80.0
    end
  end

  describe "run/1" do
    test "samples at 2/sec for the configured duration and averages them" do
      {port, listen} = start()

      try do
        assert {:ok, %{timings: timings, attempted: attempted, host: "127.0.0.1", port: ^port}} =
                 Ping.run(
                   Map.merge(@short, %{"target_host" => "127.0.0.1", "target_port" => port})
                 )

        # 2 seconds × 2 samples/sec
        assert attempted == 4
        assert length(timings) == 4
        assert Enum.all?(timings, &(&1 >= 0.0))
      after
        stop(listen)
      end
    end

    test "returns a stable error string when every connect fails" do
      port = closed_port()

      assert {:error, reason} =
               Ping.run(Map.merge(@short, %{"target_host" => "127.0.0.1", "target_port" => port}))

      assert reason =~ "TCP connect failed"
    end
  end

  # A ping streams per-sample progress over PubSub (mirroring Ookla's per-phase
  # stream) so the live view can draw samples as each connect completes. The
  # terminal {:result} still carries the final parsed measurement - progress is
  # a side-channel only, so parse/1 and run/1's return value are unchanged.
  describe "run/1 progress streaming" do
    test "broadcasts a ping_progress event as each connect completes" do
      Phoenix.PubSub.subscribe(Baudflow.PubSub, "measurements")
      {port, listen} = start()

      try do
        assert {:ok, _} =
                 Ping.run(
                   Map.merge(@short, %{"target_host" => "127.0.0.1", "target_port" => port})
                 )

        events =
          for _ <- 1..4 do
            assert_received {:ping_progress, %{host: "127.0.0.1", port: ^port} = evt}
            evt
          end

        assert Enum.map(events, & &1.sample) == [1, 2, 3, 4]
        assert Enum.map(events, & &1.total) |> Enum.uniq() == [4]

        # Cumulative counts climb to 4/4 with zero loss against a reachable
        # target, and the final sample carries a real running average.
        %{sample: 4, attempted: 4, received: 4, loss: loss, avg: avg} = List.last(events)
        assert loss == 0.0
        assert is_number(avg) and avg >= 0.0
      after
        stop(listen)
      end
    end

    test "a failed connect streams latency: nil and rising loss" do
      Phoenix.PubSub.subscribe(Baudflow.PubSub, "measurements")
      port = closed_port()

      assert {:error, _} =
               Ping.run(Map.merge(@short, %{"target_host" => "127.0.0.1", "target_port" => port}))

      events =
        for _ <- 1..4 do
          assert_received {:ping_progress, %{latency: nil, received: 0} = evt}
          evt
        end

      # Loss climbs to 100% once every attempt has failed.
      %{sample: 4, attempted: 4, received: 0, loss: loss} = List.last(events)
      assert loss == 100.0
    end
  end

  describe "binary_available?/0" do
    test "is always true - TCP needs no external binary" do
      assert Ping.binary_available?() == true
    end
  end

  describe "timeout_ms/0" do
    test "is the default duration plus grace" do
      # Default ping_duration_seconds is 10; SLA = duration + 5s grace.
      assert Ping.timeout_ms() == 15_000
    end

    test "scales with the configured run duration" do
      Baudflow.Settings.update_all(%{"ping_duration_seconds" => "20"})

      # 20s run + 5s grace - the safety net must outlast a legitimate long run.
      assert Ping.timeout_ms() == 25_000
    end
  end
end
