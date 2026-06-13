defmodule BaudflowWeb.SettingsLive do
  use BaudflowWeb, :live_view

  alias Baudflow.Settings

  @impl true
  def mount(_params, _session, socket) do
    settings = Settings.get_all()

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:active_page, :settings)
     |> assign_form(settings)}
  end

  @impl true
  def handle_event("save", %{"settings" => params}, socket) do
    # Ensure checkbox sends "false" when unchecked (hidden input handles this,
    # but belt-and-suspenders in case of edge cases)
    params = Map.put_new(params, "threshold_enabled", "false")

    cron = params["schedule_cron"] || ""

    if valid_cron?(cron) do
      :ok = Settings.update_all(params)

      {:noreply,
       socket
       |> assign_form(params)
       |> put_flash(:info, "Settings saved - schedule takes effect within 1 minute")}
    else
      {:noreply,
       put_flash(socket, :error, "Invalid cron expression: expected 5 space-separated fields")}
    end
  end

  # Settings are a key-value string store, not a schema. Build a form from the
  # plain map with `as: :settings` so fields submit under the "settings[key]"
  # namespace and render through the shared `<.input>` component.
  defp assign_form(socket, settings) do
    assign(socket, :form, to_form(settings, as: :settings))
  end

  defp valid_cron?(cron) when is_binary(cron) do
    parts = String.split(String.trim(cron), " ")
    length(parts) == 5 and Enum.all?(parts, &valid_cron_field?/1)
  end

  defp valid_cron_field?(field) do
    Regex.match?(~r/^[\d\*\/\-\,]+$/, field)
  end
end
