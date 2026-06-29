defmodule Baudflow.Notifications.PolicyTest do
  # Pure unit test - no DB. The policy is a pure function of the event + config;
  # Settings live in the worker, never here.
  use ExUnit.Case, async: true

  alias Baudflow.Notifications.{Event, Policy}

  defp event(kind, streak \\ nil), do: %Event{kind: kind, measurement_id: 1, streak: streak}

  describe "notify?/2 - breach streak gating (#21)" do
    test "fires exactly when the streak first reaches the threshold" do
      assert Policy.notify?(event(:breach, 3), %{breach_notify_streak: 3})
    end

    test "does not fire before the streak reaches the threshold" do
      refute Policy.notify?(event(:breach, 1), %{breach_notify_streak: 3})
      refute Policy.notify?(event(:breach, 2), %{breach_notify_streak: 3})
    end

    test "does not fire again once the streak has passed the threshold (reduce alert fatigue)" do
      refute Policy.notify?(event(:breach, 4), %{breach_notify_streak: 3})
      refute Policy.notify?(event(:breach, 10), %{breach_notify_streak: 3})
    end

    test "default threshold of 1 fires on the first breach" do
      assert Policy.notify?(event(:breach, 1), %{breach_notify_streak: 1})
      refute Policy.notify?(event(:breach, 2), %{breach_notify_streak: 1})
    end

    test "a breach event with no snapshot streak never fires (malformed/legacy event)" do
      refute Policy.notify?(event(:breach, nil), %{breach_notify_streak: 1})
    end
  end

  describe "notify?/2 - recovery (#22)" do
    test "fires on a recovered event" do
      assert Policy.notify?(event(:recovered), %{breach_notify_streak: 1})
    end
  end

  describe "notify?/2 - failure (#23)" do
    test "fires on a failed event" do
      assert Policy.notify?(event(:failed), %{breach_notify_streak: 1})
    end
  end

  describe "notify?/2 - healthy / steady" do
    test "never fires on a healthy event" do
      refute Policy.notify?(event(:healthy), %{breach_notify_streak: 1})
    end
  end
end
