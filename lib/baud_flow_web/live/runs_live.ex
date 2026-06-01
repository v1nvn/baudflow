defmodule BaudFlowWeb.RunsLive do
  use BaudFlowWeb, :live_view

  alias BaudFlow.Runs

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Runs")
     |> assign(:active_page, :runs)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = String.to_integer(params["page"] || "1")
    per_page = 20
    status = params["status"] || ""

    runs = Runs.list_runs_paginated(page: page, per_page: per_page, status: status)
    total = Runs.count_runs(status: status)
    status_counts = Runs.count_by_status()

    {:noreply,
     socket
     |> assign(:runs, runs)
     |> assign(:page, page)
     |> assign(:total_pages, max(1, ceil(total / per_page)))
     |> assign(:status, status)
     |> assign(:status_counts, status_counts)
     |> assign(:total_runs, total)}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    params =
      cond do
        status != "" -> %{"status" => status}
        true -> %{}
      end

    {:noreply, push_patch(socket, to: ~p"/runs?#{params}")}
  end

  defp pagination_path(page, status) do
    params =
      %{"page" => "#{page}"}
      |> maybe_put("status", status)

    ~p"/runs?#{params}"
  end

  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
