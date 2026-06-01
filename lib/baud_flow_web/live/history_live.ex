defmodule BaudFlowWeb.HistoryLive do
  use BaudFlowWeb, :live_view

  alias BaudFlow.Measurements

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "History", active_page: :history)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = String.to_integer(params["page"] || "1")
    per_page = 20

    filters = %{
      "date_from" => params["date_from"] || "",
      "date_to" => params["date_to"] || "",
      "healthy" => params["healthy"] || "",
      "server" => params["server"] || ""
    }

    sort_by = params["sort"] || "timestamp"
    sort_dir = params["dir"] || "desc"

    measurements =
      Measurements.list_paginated(
        page: page,
        per_page: per_page,
        filters: filters,
        sort_by: sort_by,
        sort_dir: sort_dir
      )

    total = Measurements.count(filters: filters)

    {:noreply,
     socket
     |> assign(:measurements, measurements)
     |> assign(:page, page)
     |> assign(:total_pages, max(1, ceil(total / per_page)))
     |> assign(:filters, filters)
     |> assign(:sort_by, sort_by)
     |> assign(:sort_dir, sort_dir)
     |> assign(:server_names, Measurements.list_server_names())}
  end

  @impl true
  def handle_event("filter", %{"filters" => filter_params}, socket) do
    params =
      %{}
      |> Map.put("page", "1")
      |> maybe_put("date_from", filter_params["date_from"])
      |> maybe_put("date_to", filter_params["date_to"])
      |> maybe_put("healthy", filter_params["healthy"])
      |> maybe_put("server", filter_params["server"])

    {:noreply, push_patch(socket, to: ~p"/history?#{params}")}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/history")}
  end

  def handle_event("sort", %{"field" => field}, socket) do
    new_dir =
      cond do
        socket.assigns.sort_by == field and socket.assigns.sort_dir == "desc" -> "asc"
        true -> "desc"
      end

    params =
      %{}
      |> Map.put("sort", field)
      |> Map.put("dir", new_dir)
      |> Map.put("page", "#{socket.assigns.page}")
      |> maybe_put("date_from", socket.assigns.filters["date_from"])
      |> maybe_put("date_to", socket.assigns.filters["date_to"])
      |> maybe_put("healthy", socket.assigns.filters["healthy"])
      |> maybe_put("server", socket.assigns.filters["server"])

    {:noreply, push_patch(socket, to: ~p"/history?#{params}")}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp pagination_path(page, filters, sort_by, sort_dir) do
    params =
      %{}
      |> Map.put("page", "#{page}")
      |> maybe_put("sort", if(sort_by == "timestamp", do: nil, else: sort_by))
      |> maybe_put("dir", if(sort_dir == "desc", do: nil, else: sort_dir))
      |> maybe_put("date_from", filters["date_from"])
      |> maybe_put("date_to", filters["date_to"])
      |> maybe_put("healthy", filters["healthy"])
      |> maybe_put("server", filters["server"])

    ~p"/history?#{params}"
  end
end
