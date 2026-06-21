defmodule Baudflow.Notifications.Policy do
  @moduledoc """
  The policy layer of the four-stage pipeline (event → policy → template →
  channel): a **pure** decision of whether to notify for an event.

  Step 0 inlined this in the worker; #21/#22/#23 make it a real module so
  streak-gating (#21), recovery (#22), and failure (#23) are config read here —
  never `if` branches smeared across a worker or a channel impl. The worker reads
  `Settings`, builds the config map, and calls `notify?/2`; this module never
  touches the DB, so it stays trivially testable.

  Semantics:

  - `:breach` fires **exactly once** when the streak first reaches the threshold
    (`event.streak == breach_notify_streak`), not `>=`. Using `==` is what makes
    #21 "reduce alert fatigue": a breach run climbing 1,2,…,N alerts only at N,
    never again, until it recovers and re-breaches. (Raising the threshold while a
    schedule is mid-breach past the new N is intentionally a no-op — we don't
    alert on a config change for an ongoing condition.)
  - `:recovered` (#22) and `:failed` (#23) fire on their transitions.
  - `:healthy` and a `:breach` whose snapshot streak is nil (malformed/legacy
    event) never fire.
  """

  alias Baudflow.Notifications.Event

  @type config :: %{breach_notify_streak: pos_integer()}

  @spec notify?(Event.t(), config()) :: boolean()
  def notify?(%Event{kind: :breach, streak: streak}, %{breach_notify_streak: threshold}),
    do: streak != nil and streak == threshold

  def notify?(%Event{kind: :recovered}, _config), do: true
  def notify?(%Event{kind: :failed}, _config), do: true

  def notify?(%Event{}, _config), do: false
end
