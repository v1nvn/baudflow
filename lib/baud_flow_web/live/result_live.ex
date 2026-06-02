defmodule BaudFlowWeb.ResultLive do
  use BaudFlowWeb, :live_view

  alias BaudFlow.Measurements

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Result", active_page: nil)}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _url, socket) do
    measurement = Measurements.get_measurement!(id)
    neighbors = Measurements.get_neighbor_ids(id)

    ref = if params["ref"] == "runs", do: :runs, else: :history

    {:noreply,
     socket
     |> assign(:measurement, measurement)
     |> assign(:older_id, neighbors.older_id)
     |> assign(:newer_id, neighbors.newer_id)
     |> assign(:ref, ref)}
  end
end
