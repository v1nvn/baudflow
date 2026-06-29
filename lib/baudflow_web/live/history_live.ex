defmodule BaudflowWeb.HistoryLive do
  use BaudflowWeb, :live_view

  alias Baudflow.Measurements

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "History", active_page: :history)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = parse_page(params["page"])
    per_page = 20

    filters = %{
      "date_from" => params["date_from"] || "",
      "date_to" => params["date_to"] || "",
      "outcome" => params["outcome"] || "",
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
     |> assign(:health_by_id, Measurements.health_states(measurements))
     |> assign(:page, page)
     |> assign(:total_pages, max(1, ceil(total / per_page)))
     |> assign(:filters, filters)
     |> assign(:sort_by, sort_by)
     |> assign(:sort_dir, sort_dir)
     |> assign(:server_names, Measurements.list_server_names())
     |> assign(:form, to_form(filters, as: :filters))}
  end

  @impl true
  def handle_event("filter", %{"filters" => filter_params}, socket) do
    params =
      %{}
      |> Map.put("page", "1")
      |> maybe_put("date_from", filter_params["date_from"])
      |> maybe_put("date_to", filter_params["date_to"])
      |> maybe_put("outcome", filter_params["outcome"])
      |> maybe_put("server", filter_params["server"])

    {:noreply, push_patch(socket, to: ~p"/history?#{params}")}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/history")}
  end

  def handle_event("sort", %{"field" => field}, socket) do
    new_dir =
      if socket.assigns.sort_by == field and socket.assigns.sort_dir == "desc",
        do: "asc",
        else: "desc"

    params =
      %{}
      |> Map.put("sort", field)
      |> Map.put("dir", new_dir)
      |> Map.put("page", "#{socket.assigns.page}")
      |> maybe_put("date_from", socket.assigns.filters["date_from"])
      |> maybe_put("date_to", socket.assigns.filters["date_to"])
      |> maybe_put("outcome", socket.assigns.filters["outcome"])
      |> maybe_put("server", socket.assigns.filters["server"])

    {:noreply, push_patch(socket, to: ~p"/history?#{params}")}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_page(nil), do: 1

  defp parse_page(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} when n >= 1 -> n
      _ -> 1
    end
  end

  # A failed test carries nil speeds - round only when present, else show "-".
  defp fmt(value, precision \\ 1)
  defp fmt(nil, _precision), do: "-"
  defp fmt(value, precision) when is_number(value), do: Float.round(value, precision)

  defp pagination_path(page, filters, sort_by, sort_dir) do
    params =
      %{}
      |> Map.put("page", "#{page}")
      |> maybe_put("sort", if(sort_by == "timestamp", do: nil, else: sort_by))
      |> maybe_put("dir", if(sort_dir == "desc", do: nil, else: sort_dir))
      |> maybe_put("date_from", filters["date_from"])
      |> maybe_put("date_to", filters["date_to"])
      |> maybe_put("outcome", filters["outcome"])
      |> maybe_put("server", filters["server"])

    ~p"/history?#{params}"
  end
end
