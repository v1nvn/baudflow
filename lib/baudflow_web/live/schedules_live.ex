defmodule BaudflowWeb.SchedulesLive do
  use BaudflowWeb, :live_view

  alias Baudflow.Scheduling
  alias Baudflow.Scheduling.Schedule
  alias Baudflow.TestRunners.RunnerWorker

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active_page, :schedules)
     |> assign(:test_types, RunnerWorker.test_types())}
  end

  # The table and the create/edit form are the same LiveView at three routes
  # (/schedules, /schedules/new, /schedules/:id/edit). push_patch makes the
  # table↔form transition near-instant and URL-addressable.
  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket |> assign(:page_title, "Schedules") |> assign_schedules()
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New schedule")
    |> assign_schedules()
    |> assign(:changeset, Schedule.changeset(%Schedule{}, %{}))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    case fetch_schedule(id) do
      nil ->
        # Stale link to a deleted schedule - bounce back to the table.
        socket |> put_flash(:error, "Schedule not found") |> push_patch(to: ~p"/schedules")

      schedule ->
        socket
        |> assign(:page_title, "Edit schedule")
        |> assign_schedules()
        |> assign(:schedule, schedule)
        |> assign(:changeset, Schedule.changeset(schedule, %{}))
    end
  end

  # --- Events -----------------------------------------------------------------

  @impl true
  def handle_event("save", %{"schedule" => attrs}, socket) do
    save(socket, socket.assigns.live_action, attrs)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case fetch_schedule(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Schedule not found")}

      schedule ->
        case Scheduling.delete(schedule) do
          {:ok, _schedule} ->
            {:noreply, socket |> assign_schedules() |> put_flash(:info, "Schedule deleted")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not delete schedule")}
        end
    end
  end

  defp save(socket, :new, attrs) do
    case Scheduling.create(normalize_attrs(attrs)) do
      {:ok, _schedule} ->
        {:noreply,
         socket |> put_flash(:info, "Schedule created") |> push_patch(to: ~p"/schedules")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:changeset, changeset)
         |> put_flash(:error, "Could not save - check the fields below")}
    end
  end

  defp save(socket, :edit, attrs) do
    case Scheduling.update(socket.assigns.schedule, normalize_attrs(attrs)) do
      {:ok, _schedule} ->
        {:noreply, socket |> put_flash(:info, "Schedule saved") |> push_patch(to: ~p"/schedules")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:changeset, changeset)
         |> put_flash(:error, "Could not save - check the fields below")}
    end
  end

  # --- State ------------------------------------------------------------------

  defp assign_schedules(socket), do: assign(socket, :schedules, Scheduling.list_schedules())

  # The id comes from a path segment or a phx-value - parse it safely (no
  # String.to_integer: banned outside Settings). Integer.parse is not banned and
  # returns :error / {int, trailing} for non-integers.
  defp fetch_schedule(id) do
    with {int, ""} <- Integer.parse(id), do: Scheduling.get_schedule(int)
  end

  # The form's `threshold_policy` select (Inherit/Auto/Absolute/Off) maps to the
  # schema's `threshold_mode` (nil/"auto"/"absolute"/"off"). The single threshold
  # reader `Scheduling.thresholds_for/1` resolves nil to the global fallback, so
  # "inherit" is honored. On "inherit" we nil the per-schedule value fields so a
  # switch back clears stale overrides.
  defp normalize_attrs(attrs) do
    attrs
    |> Map.delete("threshold_policy")
    |> apply_threshold_policy(attrs["threshold_policy"] || "inherit")
  end

  defp apply_threshold_policy(attrs, "inherit") do
    attrs
    |> Map.put("threshold_mode", nil)
    |> Map.put("download", nil)
    |> Map.put("upload", nil)
    |> Map.put("ping", nil)
  end

  defp apply_threshold_policy(attrs, policy) when policy in ~w(auto absolute off) do
    Map.put(attrs, "threshold_mode", policy)
  end

  # --- Template helpers -------------------------------------------------------

  # Policy comes from the changeset so it survives a failed submit.
  defp threshold_policy(changeset) do
    case Ecto.Changeset.get_field(changeset, :threshold_mode) do
      "auto" -> "auto"
      "absolute" -> "absolute"
      "off" -> "off"
      _ -> "inherit"
    end
  end

  # --- Function components ----------------------------------------------------

  attr :form, :any, required: true
  attr :policy, :string, required: true

  def schedule_threshold_fields(assigns) do
    ~H"""
    <div class="space-y-3 pt-3 border-t border-border">
      <div class="flex items-center gap-3">
        <span class="text-xs font-medium text-text-dim uppercase tracking-wider">Thresholds</span>
        <select
          name="schedule[threshold_policy]"
          class="bf-input !w-auto !py-1"
          aria-label="Threshold policy"
        >
          <option value="inherit" selected={@policy == "inherit"}>Inherit (global)</option>
          <option value="auto" selected={@policy == "auto"}>Auto (relative)</option>
          <option value="absolute" selected={@policy == "absolute"}>Absolute</option>
          <option value="off" selected={@policy == "off"}>Off</option>
        </select>
      </div>
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <.input
          field={@form[:download]}
          type="number"
          label="Min Download (Mbps)"
          class="bf-input"
          min="0"
          step="any"
          placeholder="blank = inherit"
        />
        <.input
          field={@form[:upload]}
          type="number"
          label="Min Upload (Mbps)"
          class="bf-input"
          min="0"
          step="any"
          placeholder="blank = inherit"
        />
        <.input
          field={@form[:ping]}
          type="number"
          label="Max Ping (ms)"
          class="bf-input"
          min="0"
          step="any"
          placeholder="blank = inherit"
        />
      </div>
    </div>
    """
  end
end
