defmodule Baudflow.TestRunners.TestRunner do
  @moduledoc """
  Behaviour for a test backend (`Ookla` today; `Ping`/`iPerf3` later).

  An impl runs the test (`run/1`, streaming its own per-phase progress over
  PubSub) and maps its native result shape to measurement attrs (`parse/1`).
  The `RunnerWorker` resolves the impl by `test_type` and owns the pipeline -
  insert, run record, terminal broadcast, downstream enqueue - never the impl.
  """

  @type run_result ::
          {:ok, map()}
          | {:error, :timeout}
          | {:error, {:cli_exit, integer(), String.t()}}
          | {:error, String.t()}

  @doc """
  Run the test. Streams progress over PubSub as the impl sees fit and returns
  the final result on success, or one of the error shapes on failure.
  """
  @callback run(args :: map()) :: run_result()

  @doc "Map the impl's native result into the measurement attrs shape."
  @callback parse(result :: map()) :: map()

  @doc "Whether the impl's binary is available on this host."
  @callback binary_available?() :: boolean()

  @doc "The impl's SLA in milliseconds (worst-case runtime for safety nets)."
  @callback timeout_ms() :: non_neg_integer()
end
