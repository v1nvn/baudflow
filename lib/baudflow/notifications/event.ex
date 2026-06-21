defmodule Baudflow.Notifications.Event do
  @moduledoc """
  Closed, typed event vocabulary for the pipeline.

  `kind` is one of `:healthy | :breach | :recovered | :failed`. Constructed ONLY
  in `Baudflow.Health` (the single state owner) — every other module reads
  events, never builds them. The companion credo rule (batch 4) enforces that
  once webhooks arrive.

  `streak` is the breach streak snapshotted at construction (a `:breach` event
  carries the value just written, so the policy can gate on it without rereading
  the schedule row across the async Oban boundary). nil for non-breach events.
  """

  @enforce_keys [:kind, :measurement_id]
  defstruct [:kind, :measurement_id, :schedule_id, :streak]

  @kinds [:healthy, :breach, :recovered, :failed]
  @string_to_kind Enum.into(@kinds, %{}, fn k -> {Atom.to_string(k), k} end)

  @type kind :: :healthy | :breach | :recovered | :failed
  @type t :: %__MODULE__{
          kind: kind(),
          measurement_id: integer(),
          schedule_id: integer() | nil,
          streak: integer() | nil
        }

  @doc "The closed set of valid event kinds."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc """
  Reconstruct an event from its Oban args (the shape Health enqueues).

  Maps the kind string back to a known atom via the closed `@kinds` set — never
  `String.to_atom/1` on input.
  """
  @spec from_args(map()) :: t()
  def from_args(%{"kind" => kind, "measurement_id" => id} = args) do
    %__MODULE__{
      kind: Map.fetch!(@string_to_kind, kind),
      measurement_id: id,
      schedule_id: args["schedule_id"],
      streak: args["streak"]
    }
  end
end
