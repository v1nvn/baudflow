defmodule BaudflowWeb.SettingsLive do
  use BaudflowWeb, :live_view

  alias Baudflow.Scheduling
  alias Baudflow.Scheduling.Schedule
  alias Baudflow.Settings

  @impl true
  def mount(_params, _session, socket) do
    # The cron card edits the default schedule row (scheduling is data), so its
    # value comes from the schedule, not the legacy key/value setting.
    settings =
      Settings.get_all()
      |> Map.put("schedule_cron", default_schedule_cron())

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
      :ok = save_schedule_cron(cron)

      # the rest of the card is plain key/value settings
      rest = Map.delete(params, "schedule_cron")
      :ok = Settings.update_all(rest)

      {:noreply,
       socket
       |> assign_form(Map.put(rest, "schedule_cron", cron))
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

  defp default_schedule_cron do
    case Scheduling.list_schedules() do
      [%Schedule{cron: cron} | _] -> cron
      [] -> "0 * * * *"
    end
  end

  defp save_schedule_cron(cron) do
    case Scheduling.list_schedules() do
      [schedule | _] ->
        {:ok, _} = Scheduling.update(schedule, %{cron: cron})
        :ok

      [] ->
        {:ok, _} = Scheduling.create(%{name: "Default", cron: cron, enabled: true})
        :ok
    end
  end

  defp valid_cron?(cron) when is_binary(cron) do
    parts = String.split(String.trim(cron), " ")
    length(parts) == 5 and Enum.all?(parts, &valid_cron_field?/1)
  end

  defp valid_cron_field?(field) do
    Regex.match?(~r/^[\d\*\/\-\,]+$/, field)
  end
end
