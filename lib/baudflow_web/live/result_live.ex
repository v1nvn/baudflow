defmodule BaudflowWeb.ResultLive do
  use BaudflowWeb, :live_view

  alias Baudflow.Measurements

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Result", active_page: nil)}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _url, socket) do
    measurement = Measurements.get_measurement!(id)
    neighbors = Measurements.get_neighbor_ids(id)

    ref = if params["ref"] == "runs", do: :runs, else: :history

    # State and the per-check breakdown both come from the one JIT call, so the
    # pill and the metric rows can't disagree (or drift from the stored snapshot).
    {state, benchmarks} = Measurements.health(measurement)

    {:noreply,
     socket
     |> assign(:measurement, measurement)
     |> assign(:health, state)
     |> assign(:benchmarks, benchmarks)
     |> assign(:older_id, neighbors.older_id)
     |> assign(:newer_id, neighbors.newer_id)
     |> assign(:ref, ref)}
  end
end
