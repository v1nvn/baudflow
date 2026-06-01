defmodule BaudFlowWeb.SettingsLive do
  use BaudFlowWeb, :live_view

  alias BaudFlow.Settings

  @impl true
  def mount(_params, _session, socket) do
    settings = Settings.get_all()

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:active_page, :settings)
     |> assign_settings(settings)}
  end

  @impl true
  def handle_event("save", %{"settings" => params}, socket) do
    # Ensure checkbox sends "false" when unchecked (hidden input handles this,
    # but belt-and-suspenders in case of edge cases)
    params = Map.put_new(params, "threshold_enabled", "false")

    cron = params["schedule_cron"] || ""

    cond do
      not valid_cron?(cron) ->
        {:noreply,
         put_flash(socket, :error, "Invalid cron expression: expected 5 space-separated fields")}

      true ->
        :ok = Settings.update_all(params)

        {:noreply,
         socket
         |> assign_settings(params)
         |> put_flash(:info, "Settings saved — schedule takes effect within 1 minute")}
    end
  end

  defp assign_settings(socket, settings) do
    socket
    |> assign(:schedule_cron, settings["schedule_cron"])
    |> assign(:preferred_servers, settings["preferred_servers"])
    |> assign(:blocked_servers, settings["blocked_servers"])
    |> assign(:retention_days, settings["retention_days"])
    |> assign(:degradation_threshold, settings["degradation_threshold"])
    |> assign(:dashboard_points, settings["dashboard_points"])
    |> assign(:threshold_enabled, settings["threshold_enabled"])
    |> assign(:threshold_download, settings["threshold_download"])
    |> assign(:threshold_upload, settings["threshold_upload"])
    |> assign(:threshold_ping, settings["threshold_ping"])
  end

  defp valid_cron?(cron) when is_binary(cron) do
    parts = String.split(String.trim(cron), " ")
    length(parts) == 5 and Enum.all?(parts, &valid_cron_field?/1)
  end

  defp valid_cron_field?(field) do
    Regex.match?(~r/^[\d\*\/\-\,]+$/, field)
  end
end
