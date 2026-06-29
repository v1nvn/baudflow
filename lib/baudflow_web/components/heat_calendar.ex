defmodule BaudflowWeb.HeatCalendar do
  @moduledoc """
  Calendar shaping for the health heatmap tiles, painted client-side by the
  `HeatmapMatrix` hook (chartjs-chart-matrix). The date math lives here so the
  hook stays a dumb plotter and the layout is unit-testable: a day's matrix
  position (weekday column, week-of-month row) is a pure function of its date.
  """

  use Phoenix.Component

  # ISO weekday (1=Mon..7=Sun) → column label, Monday-first.
  @weekday_labels ~w(Mon Tue Wed Thu Fri Sat Sun)
  @month_names ~w(January February March April May June July August September October November December)

  @doc """
  Legend statuses in display order - the single source of truth for status
  wording. The legend renders it directly, and `status_labels/1` ships it to the
  `HeatmapMatrix` tooltip via the canvas `data-labels`, so the two can't drift.

  `unknown_label` is caller-supplied (the view resolves the global threshold
  mode once and passes it): "Calibrating" under `:auto` (a nil verdict means the
  baseline isn't ready yet), "No verdict" otherwise. The component never reads
  `Settings` itself - it stays a dumb renderer shared by every placement.
  """
  def statuses(unknown_label \\ "No verdict") do
    [
      {:healthy, "Healthy"},
      {:breach, "Threshold breach"},
      {:failed, "Failed"},
      {:unknown, unknown_label},
      {:empty, "No data"}
    ]
  end

  @doc """
  The no-verdict wording for a given health `mode` - "Calibrating" under `:auto`
  (a nil verdict means the rolling baseline isn't ready yet) vs "No verdict"
  otherwise. The single owner of this wording; views pass it to `heat_tile`/
  `heat_legend` so the dumb renderer never reads `Settings` to decide it.
  """
  def unknown_label(:auto), do: "Calibrating"
  def unknown_label(_mode), do: "No verdict"

  @doc """
  Muted health palette - the same hues as the line-chart neon but desaturated
  and lowered in lightness, so a wall of cells reads as a calm field rather than
  a grid of lasers. Single source of truth: the legend swatches and the
  `HeatmapMatrix` hook (via the canvas `data-colors`) both consume this map, so
  they can never drift apart.
  """
  def status_colors do
    %{
      "healthy" => "#3a9d7a",
      "breach" => "#c29438",
      "failed" => "#c75566",
      "unknown" => "#2c3852"
    }
  end

  def status_colors_json, do: Jason.encode!(status_colors())

  @doc """
  Status labels keyed by the string the matrix cells carry (the `v` field),
  derived from `statuses/1`. Shipped to the hook via the canvas `data-labels`,
  parallel to `status_colors`/`data-colors` - the JS maps are only fallbacks.
  """
  def status_labels(unknown_label \\ "No verdict") do
    Map.new(statuses(unknown_label), fn {key, label} -> {Atom.to_string(key), label} end)
  end

  def status_labels_json(unknown_label \\ "No verdict"),
    do: Jason.encode!(status_labels(unknown_label))

  @doc """
  UTC midnight on the first day of `date`'s month - the lower bound for "this
  month's" heatmap window. The dashboard widget and the embed both fetch the
  current month this way; the wall grid at `/heatmap` does not (full history).
  """
  def month_start(%Date{} = date) do
    DateTime.new!(Date.new!(date.year, date.month, 1), ~T[00:00:00], "Etc/UTC")
  end

  @doc """
  Build one month tile: `%{id, label, weeks, cells}`. `cells` is one
  `{x, y, v, d}` per calendar day - `x` the ISO weekday column label (Mon-first),
  `y` the zero-based week-of-month row, `v` the worst health status as a string
  (`"empty"` when the day has no bucket), `d` the ISO date for the tooltip.
  `weeks` is the row count so the hook can size its cells.
  """
  def month_matrix(year, month, status_by_date, id) do
    first = Date.new!(year, month, 1)
    days = Date.days_in_month(first)
    first_weekday = Date.day_of_week(first)

    cells =
      for day <- 1..days do
        date = Date.new!(year, month, day)
        status = Map.get(status_by_date, date, :empty)

        %{
          x: Enum.at(@weekday_labels, Date.day_of_week(date) - 1),
          y: Integer.to_string(week_row(day, first_weekday)),
          v: Atom.to_string(status),
          d: Date.to_iso8601(date)
        }
      end

    %{
      id: id,
      label: Enum.at(@month_names, month - 1) <> " #{year}",
      weeks: week_row(days, first_weekday) + 1,
      cells: cells
    }
  end

  # Zero-based week-of-month row for `day` (1-based), given the ISO weekday
  # (1=Mon..7=Sun) of the 1st. ISO weeks start Monday, so the row advances each
  # Monday: week 0 holds days [1 .. (8 - first_weekday)].
  defp week_row(day, first_weekday) do
    div(day - 1 + (first_weekday - 1), 7)
  end

  @doc """
  Renders one month tile: a label plus the canvas the `HeatmapMatrix` hook
  paints on. Deliberately chrome-less - the caller wraps it (a `glass-card` on
  the wall grid, the dashboard's existing card, a bare container on the embed)
  so the same component serves all three placements.
  """
  attr :tile, :map, required: true, doc: "a `month_matrix/4` result"
  attr :compact, :boolean, default: false, doc: "smaller label + cells for the dashboard widget"

  attr :unknown_label, :string,
    default: "No verdict",
    doc: "tooltip + legend word for a no-verdict cell"

  def heat_tile(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-1.5">
        <span class={["font-medium text-text-dim", if(@compact, do: "text-[10px]", else: "text-xs")]}>
          {@tile.label}
        </span>
      </div>
      <div class={["w-full", @compact && "max-w-[190px] mx-auto"]}>
        <canvas
          id={@tile.id}
          phx-hook="HeatmapMatrix"
          data-weeks={@tile.weeks}
          data-colors={status_colors_json()}
          data-labels={status_labels_json(@unknown_label)}
        >
        </canvas>
      </div>
    </div>
    """
  end

  @doc """
  The status legend, shared by every heatmap placement so the wording and order
  match the `HeatmapMatrix` color scale.
  """
  attr :compact, :boolean, default: false
  attr :unknown_label, :string, default: "No verdict"

  def heat_legend(assigns) do
    ~H"""
    <div class={[
      "flex flex-wrap items-center gap-x-3 gap-y-1 text-text-ghost",
      if(@compact, do: "justify-center text-[10px]", else: "text-xs")
    ]}>
      <span :for={{key, label} <- statuses(@unknown_label)} class="flex items-center gap-1.5">
        <span
          class={["size-2.5 rounded-sm", key == :empty && "border border-border-subtle"]}
          style={swatch_style(key)}
        />
        {label}
      </span>
    </div>
    """
  end

  # `:empty` has no fill - it's a faint outlined cell - so it returns no inline
  # style and the border utility does the work.
  defp swatch_style(:empty), do: nil

  defp swatch_style(key),
    do: "background-color: #{Map.fetch!(status_colors(), Atom.to_string(key))}"
end
