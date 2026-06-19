defmodule Baudflow.Notifications.Payload do
  @moduledoc """
  The resolved context carried between pipeline layers (policy → template →
  channel). Bundles the event with its measurement so a channel never reaches
  back into a worker, and a webhook (#24) can render the same context as JSON.
  """

  @enforce_keys [:event, :measurement]
  defstruct [:event, :measurement]

  alias Baudflow.Measurements.Measurement
  alias Baudflow.Notifications.Event

  @type t :: %__MODULE__{
          event: Event.t(),
          measurement: Measurement.t() | nil
        }
end
