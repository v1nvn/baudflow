defmodule BaudflowWeb.SettingsLive do
  use BaudflowWeb, :live_view

  alias Baudflow.Notifications.Template
  alias Baudflow.Settings

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:active_page, :settings)
     # The webhook template textarea placeholder is the built-in default — the
     # single source of truth lives in Template, so the UI never drifts from it.
     |> assign(:webhook_template_default, Template.default(:webhook))
     |> assign_form(Settings.get_all())}
  end

  @impl true
  def handle_event("save", %{"settings" => params}, socket) do
    # An unchecked checkbox is omitted from params; default it to "false".
    params = Map.put_new(params, "threshold_enabled", "false")
    :ok = Settings.update_all(params)

    {:noreply,
     socket
     |> assign_form(params)
     |> put_flash(:info, "Settings saved")}
  end

  # Settings are a key-value string store, not a schema. Build a form from the
  # plain map with `as: :settings` so fields submit under the "settings[key]"
  # namespace and render through the shared `<.input>` component.
  #
  # Schedule cadence + per-schedule thresholds live on the `Schedule` row now
  # (#12 multiple schedules) — managed at `/schedules`, not here. The global
  # threshold fields below remain as the inherited fallback (`thresholds_for/1`).
  defp assign_form(socket, settings) do
    assign(socket, :form, to_form(settings, as: :settings))
  end
end
