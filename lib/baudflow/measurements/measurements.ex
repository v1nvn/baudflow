defmodule Baudflow.Measurements do
  @moduledoc """
  Context for speedtest measurement results.
  """
  import Ecto.Query
  alias Baudflow.Health
  alias Baudflow.Measurements.Measurement
  alias Baudflow.Repo
  alias Baudflow.Scheduling

  # Window for the /metrics uptime gauge (healthy share). Matches the dashboard's
  # max range. A module attr, not a setting - promote to Settings only if it
  # becomes user-facing.
  @uptime_window_days 30

  # :auto-mode rolling baseline: median of the prior N days, deemed trustworthy
  # only past this many qualifying samples (below = "calibrating", no verdict).
  @baseline_window_days 7
  @baseline_min_samples 12

  @typedoc "A measurement's JIT health state - derived on read, never stored."
  @type state :: :healthy | :breach | :failed | :unknown

  @doc "Create a measurement from a parsed test-result attributes map."
  def create_measurement(attrs) do
    Measurement.from_result(attrs)
    |> Repo.insert()
  end

  @doc """
  Insert a measurement marking a failed test - no speed/ping data, just a
  timestamped failure point on the timeline (`failed: true`).

  The runner writes this on every test-failure path so an outage is visible on
  the chart instead of a silent gap. Speeds stay nil, so `avg()`/`compliance`
  exclude it; Health is not evaluated (a failed test has no thresholds to check).
  `test_type` defaults to `"ookla"` and `source` to `"scheduled"`.
  """
  def record_failure(attrs) do
    attrs =
      attrs
      |> Map.put_new(:source, "scheduled")
      |> Map.put_new(:test_type, "ookla")
      |> Map.put(:failed, true)

    Measurement.from_result(attrs)
    |> Repo.insert()
  end

  @doc "Get a measurement by ID, raises if not found."
  def get_measurement!(id) do
    Repo.get!(Measurement, id)
  end

  @doc "Get a measurement by ID, returns nil if not found."
  def get_measurement(id) do
    Repo.get(Measurement, id)
  end

  @doc "List recent measurements, newest first, limited to `limit`."
  def list_recent(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    from(m in Measurement,
      order_by: [desc: m.timestamp],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  List measurements since a given datetime, newest first.

  Pass `test_type:` to scope to one impl - the dashboard uses `"ookla"` so ping
  results (which carry no speed) don't pollute the speed chart.
  """
  def list_since(since, opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)
    test_type = Keyword.get(opts, :test_type)

    Measurement
    |> maybe_filter_test_type(test_type)
    |> where([m], m.timestamp > ^since)
    |> order_by([m], desc: m.timestamp)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "List measurements paginated by page/per_page with optional filters and sort."
  def list_paginated(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    offset = (page - 1) * per_page
    filters = Keyword.get(opts, :filters, %{})
    sort_by = Keyword.get(opts, :sort_by, "timestamp")
    sort_dir = Keyword.get(opts, :sort_dir, "desc")

    from(m in Measurement)
    |> apply_filters(filters)
    |> apply_sort(sort_by, sort_dir)
    |> limit(^per_page)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc "Count total measurements, optionally filtered."
  def count(opts \\ []) do
    filters = Keyword.get(opts, :filters, %{})

    from(m in Measurement, select: count(m.id))
    |> apply_filters(filters)
    |> Repo.one()
  end

  @doc "List distinct server names for filter dropdown."
  def list_server_names do
    from(m in Measurement,
      select: m.server_name,
      distinct: true,
      where: not is_nil(m.server_name) and m.server_name != "",
      order_by: m.server_name
    )
    |> Repo.all()
  end

  @doc """
  Persist the per-check `benchmarks` snapshot from a health evaluation. The
  verdict itself is derived JIT (never stored) - this only saves the detail the
  result page and notification template render.
  """
  def update_benchmarks(measurement, benchmarks) do
    Measurement.benchmarks_changeset(measurement, %{benchmarks: benchmarks})
    |> Repo.update()
  end

  @doc """
  JIT health for a single measurement: `{state, benchmarks}`. `state` is
  `:healthy | :breach | :failed | :unknown`; `benchmarks` is the per-check map
  (`nil` when there's no verdict). Derived on read - never stored - so changing
  the mode/ratio re-derives every view on the next read. `:auto` judges the
  measurement against its own point-in-time trailing median (`baseline_for/2`),
  `:absolute` against the fixed thresholds, `:off` yields `:unknown`.
  """
  @spec health(Measurement.t()) :: {state(), map() | nil}
  def health(%Measurement{failed: true}), do: {:failed, nil}

  def health(%Measurement{} = measurement) do
    thresholds = Scheduling.global_thresholds()
    evaluate(measurement, thresholds, baseline_for(measurement, thresholds))
  end

  @doc "The `state` half of `health/1` (`:healthy | :breach | :failed | :unknown`)."
  @spec health_state(Measurement.t()) :: state()
  def health_state(%Measurement{} = measurement), do: elem(health(measurement), 0)

  @doc """
  Batch JIT state as `%{id => state}` for a list of measurements - the history
  table's per-row badge. Point-in-time and per-`test_type` correct (so a row's
  badge matches its result-detail badge), computed from one baseline pool fetched
  for the whole list rather than a per-row query.
  """
  @spec health_states([Measurement.t()]) :: %{integer() => state()}
  def health_states(measurements) do
    thresholds = Scheduling.global_thresholds()
    baselines = batch_baselines(thresholds, measurements, &baseline_pool/1)

    Map.new(measurements, fn m ->
      {state, _benchmarks} = evaluate(m, thresholds, Map.get(baselines, m.id, :insufficient))
      {m.id, state}
    end)
  end

  @doc """
  The `:auto` rolling baseline for a single measurement (`nil` outside `:auto`) -
  the one place a single measurement's baseline is sourced, shared by the live
  `HealthWorker` and every JIT reader. `%{download, upload, ping}` or
  `:insufficient` while calibrating.
  """
  @spec baseline_for(Measurement.t(), map()) :: map() | :insufficient | nil
  def baseline_for(_measurement, %{mode: mode}) when mode != :auto, do: nil

  def baseline_for(%Measurement{timestamp: at, test_type: test_type}, _thresholds),
    do: trailing_median(at, test_type)

  @doc """
  Delete all measurements strictly older than `cutoff` timestamp.
  Returns the number of deleted rows.
  """
  def prune_older_than(cutoff) do
    {count, _} =
      Repo.delete_all(
        from(m in Measurement,
          where: m.timestamp < ^cutoff
        )
      )

    count
  end

  @doc "Compute 7-day and 30-day average download Mbps, excluding manual entries."
  def window_averages do
    %{
      avg_7d: rolling_average(7),
      avg_30d: rolling_average(30)
    }
  end

  @doc """
  Average download Mbps over the last `days` days, excluding manual entries.
  Returns `nil` when there are no qualifying measurements.
  """
  def rolling_average(days) do
    since = DateTime.add(DateTime.utc_now(), -days * 24 * 3600, :second)
    average_download_since(since)
  end

  defp average_download_since(since) do
    Repo.one(
      from(m in Measurement,
        where: m.timestamp > ^since and m.source != "manual",
        select: avg(m.download_mbps)
      )
    )
  end

  @doc """
  Share of speed tests (in a window since `since`) that met the promised speeds.

  `promised_download`/`promised_upload` are the ISP-plan numbers from `Settings`
  (`0` = none). Returns `nil` when neither promise is configured; otherwise
  `%{meeting: n, total: n, percent: float | nil}`, where `percent` is `nil` only
  when no speed tests exist in the window. A test counts as compliant when it
  meets every configured (non-zero) promise; a ping result (nil download) never
  counts, and a failed speed test with no download number is excluded too.
  """
  def compliance(opts \\ []) do
    since = Keyword.fetch!(opts, :since)
    promised_download = Keyword.get(opts, :promised_download, 0.0)
    promised_upload = Keyword.get(opts, :promised_upload, 0.0)

    if promised_download <= 0.0 and promised_upload <= 0.0 do
      nil
    else
      base = from(m in Measurement, where: m.timestamp > ^since and not is_nil(m.download_mbps))
      total = base |> select([m], count(m.id)) |> Repo.one()

      meeting =
        base
        |> maybe_require_download(promised_download)
        |> maybe_require_upload(promised_upload)
        |> select([m], count(m.id))
        |> Repo.one()

      %{meeting: meeting, total: total, percent: percent_of(meeting, total)}
    end
  end

  @doc """
  Bucket measurements by UTC day, returning per-day health counts - derived
  just-in-time, never read off a stored verdict (verdicts aren't persisted; see
  `Baudflow.Health`). Same output shape the heatmap and `/metrics` consume:

      %{bucket: DateTime, total: n, healthy: n, breach: n, failed: n, unknown: n}

  Opts: `:since` (optional `DateTime` lower bound - omit/`nil` for full history),
  `:test_type` (scope to one runner; the heatmap passes `"ookla"`).

  Each row's verdict comes from `evaluate/3` against the global thresholds; in
  `:auto` the baselines are the point-in-time trailing medians over the fetched
  window (`trailing_baselines/2`, one pass per `test_type` - no per-row query, no
  stored column to backfill). `failed` rows are always `:failed`. `[]` when
  nothing matches.
  """
  def health_buckets(opts \\ []) do
    since = Keyword.get(opts, :since)
    test_type = Keyword.get(opts, :test_type)
    thresholds = Scheduling.global_thresholds()

    measurements =
      from(m in Measurement)
      |> maybe_filter_test_type(test_type)
      |> maybe_since(since)
      |> order_by([m], asc: m.timestamp)
      |> Repo.all()

    baselines = batch_baselines(thresholds, measurements, & &1)

    measurements
    |> Enum.map(fn m ->
      {state, _benchmarks} = evaluate(m, thresholds, Map.get(baselines, m.id, :insufficient))
      %{bucket: day_bucket(m.timestamp), state: state}
    end)
    |> pivot_states()
  end

  @doc """
  Rolling-median baseline at a point in time for `:auto` health: the median
  download/upload/ping of the prior `@baseline_window_days` days for `test_type`,
  excluding failed and manual rows. Returns `%{download, upload, ping}` or
  `:insufficient` when fewer than `@baseline_min_samples` qualifying rows exist
  (no verdict while calibrating). Sourced for single measurements via
  `baseline_for/2`; the list consumers (`health_buckets`/`health_states`) compute
  baselines in-memory over a fetched window (`trailing_baselines/2`) instead.
  """
  @spec trailing_median(DateTime.t(), String.t(), keyword()) :: map() | :insufficient
  def trailing_median(at, test_type, opts \\ []) do
    days = Keyword.get(opts, :days, @baseline_window_days)
    since = DateTime.add(at, -days * 24 * 3600, :second)

    row =
      from(m in Measurement,
        where:
          m.test_type == ^test_type and m.timestamp > ^since and m.timestamp < ^at and
            not m.failed and m.source != "manual"
      )
      |> select([m], %{
        count: count(m.id),
        download: fragment("percentile_cont(0.5) WITHIN GROUP (ORDER BY ?)", m.download_mbps),
        upload: fragment("percentile_cont(0.5) WITHIN GROUP (ORDER BY ?)", m.upload_mbps),
        ping: fragment("percentile_cont(0.5) WITHIN GROUP (ORDER BY ?)", m.ping_latency)
      })
      |> Repo.one()

    if row && row.count >= Keyword.get(opts, :min_samples, @baseline_min_samples) do
      row
    else
      :insufficient
    end
  end

  @doc """
  Scalar medians over a window (since, test_type) for the dashboard chart's
  `:auto` reference line - a flat annotation, not a rolling series.
  """
  @spec window_median(DateTime.t(), String.t()) :: %{
          download: float() | nil,
          upload: float() | nil,
          ping: float() | nil
        }
  def window_median(since, test_type) do
    from(m in Measurement,
      where:
        m.test_type == ^test_type and m.timestamp > ^since and not m.failed and
          m.source != "manual"
    )
    |> select([m], %{
      download: fragment("percentile_cont(0.5) WITHIN GROUP (ORDER BY ?)", m.download_mbps),
      upload: fragment("percentile_cont(0.5) WITHIN GROUP (ORDER BY ?)", m.upload_mbps),
      ping: fragment("percentile_cont(0.5) WITHIN GROUP (ORDER BY ?)", m.ping_latency)
    })
    |> Repo.one()
    |> Kernel.||(%{download: nil, upload: nil, ping: nil})
  end

  @doc """
  Worst health status of a bucket row from `health_buckets/1`, in priority order
  `failed > breach > healthy > unknown`. A real bucket always has `total >= 1`,
  so this never returns `:empty` for queried data - `:empty` is the caller's
  default for a calendar cell with no bucket. Pure; the only caller is
  `daily_health/1`, which reduces a day's counts to this one status.
  """
  def bucket_status(%{failed: n}) when n > 0, do: :failed
  def bucket_status(%{breach: n}) when n > 0, do: :breach
  def bucket_status(%{healthy: n}) when n > 0, do: :healthy
  def bucket_status(%{unknown: n}) when n > 0, do: :unknown
  def bucket_status(_), do: :empty

  @doc """
  Daily health map for the heatmap tiles: `%{Date => status}` over the window,
  where `status` is the worst health of the day from `bucket_status/1`. `:since`
  is optional (omit/`nil` for full history - the wall grid uses that); scoped to
  `test_type: "ookla"` by default. Calendar shaping (weekday/week coordinates)
  is the view's job - this only answers "what color is this day?" so all three
  consumers (dashboard, wall grid, embed) share one lookup. A day with no bucket
  is simply absent from the map; the view treats absence as "no data" cell.
  """
  def daily_health(opts \\ []) do
    since = Keyword.get(opts, :since)
    test_type = Keyword.get(opts, :test_type, "ookla")

    health_buckets(since: since, test_type: test_type)
    |> Map.new(fn row ->
      {DateTime.to_date(row.bucket), bucket_status(row)}
    end)
  end

  @doc """
  Snapshot for the Prometheus `/metrics` endpoint: the latest Ookla measurement,
  the total retained count, and the healthy share over the uptime window. The
  single source - the metrics controller formats this map and queries nothing
  else.

  `latest` is `nil` only on a fresh install with no Ookla tests. `uptime` is
  `%{healthy, total, percent}`, where `percent` is `nil` when the window has no
  tests (distinct from `0.0`). The window defaults to 30 days (`days:` to
  override). Uptime is computed over **all** test types in the window via the
  existing `health_buckets/1` aggregation (one query, one place).
  """
  def metrics(opts \\ []) do
    latest = latest_ookla()

    %{
      latest: latest,
      total: count(),
      uptime: uptime(opts),
      health: latest_health(latest)
    }
  end

  # JIT verdict for the /metrics health gauge: `:healthy`/`:breach` map to 1/0,
  # while nil (calibrating, off mode, a failed test, or no latest) omits the gauge.
  defp latest_health(nil), do: nil

  defp latest_health(%Measurement{} = latest) do
    case health_state(latest) do
      :healthy -> true
      :breach -> false
      _ -> nil
    end
  end

  defp latest_ookla do
    from(m in Measurement,
      where: m.test_type == "ookla",
      order_by: [desc: m.timestamp],
      limit: 1
    )
    |> Repo.one()
  end

  defp uptime(opts) do
    days = Keyword.get(opts, :days, @uptime_window_days)
    since = DateTime.add(DateTime.utc_now(), -days * 24 * 3600, :second)

    # Reuse the existing per-day health aggregation (all test types, windowed),
    # then reduce to window totals - no second health-aggregation query path.
    buckets = health_buckets(since: since)
    total = Enum.reduce(buckets, 0, fn b, acc -> acc + b.total end)
    healthy = Enum.reduce(buckets, 0, fn b, acc -> acc + b.healthy end)
    percent = if total == 0, do: nil, else: Float.round(healthy / total * 100, 1)

    %{healthy: healthy, total: total, percent: percent}
  end

  # `since: nil` means no lower bound - the wall grid fetches full history. A
  # dedicated clause keeps the unbounded query off the `where` plan entirely.
  defp maybe_since(query, nil), do: query

  defp maybe_since(query, %DateTime{} = since),
    do: where(query, [m], m.timestamp > ^since)

  # One `{bucket, state}` per measurement → per-day state counts, ascending by
  # bucket. `bucket` is a UTC-midnight DateTime so `daily_health`/`uptime` keep
  # their existing `DateTime.to_date`/`DateTime` sort handling.
  defp pivot_states(states) do
    states
    |> Enum.group_by(& &1.bucket)
    |> Enum.map(fn {bucket, group} ->
      counts =
        Enum.reduce(group, %{healthy: 0, breach: 0, failed: 0, unknown: 0}, fn %{state: s}, acc ->
          Map.update!(acc, s, &(&1 + 1))
        end)

      total = counts.healthy + counts.breach + counts.failed + counts.unknown
      Map.merge(counts, %{bucket: bucket, total: total})
    end)
    |> Enum.sort_by(& &1.bucket, DateTime)
  end

  # Measurement + resolved thresholds + baseline → `{state, benchmarks}`. The one
  # place a verdict becomes a state atom; every reader (single, batch, buckets)
  # funnels through here. A failed test is `:failed` with no benchmarks.
  defp evaluate(%Measurement{failed: true}, _thresholds, _baseline), do: {:failed, nil}

  defp evaluate(%Measurement{} = measurement, thresholds, baseline) do
    case Health.verdict(measurement, thresholds, baseline) do
      {true, benchmarks} -> {:healthy, benchmarks}
      {false, benchmarks} -> {:breach, benchmarks}
      {nil, _benchmarks} -> {:unknown, nil}
    end
  end

  # Per-id `:auto` baselines for a list (`%{}` outside `:auto`). `pool_fun` yields
  # the rows the in-memory sliding window draws from: the list itself for the
  # full-history aggregate (`& &1`), a fetched prior-window pool for a page.
  defp batch_baselines(%{mode: :auto}, measurements, pool_fun),
    do: trailing_baselines(measurements, pool_fun.(measurements))

  defp batch_baselines(_thresholds, _measurements, _pool_fun), do: %{}

  # Per-id baselines via one forward pass per `test_type`: each target's baseline
  # is the median of eligible `pool` rows in `(timestamp − @baseline_window_days,
  # timestamp)`, scoped to its own test_type. The sliding window over the
  # timestamp-sorted lists keeps the full-history wall grid O(n) rather than
  # rescanning the pool per row. `:insufficient` below the min sample count.
  defp trailing_baselines(targets, pool) do
    pool_by_type =
      pool
      |> Enum.filter(&baseline_eligible?/1)
      |> Enum.group_by(& &1.test_type)

    targets
    |> Enum.group_by(& &1.test_type)
    |> Enum.flat_map(fn {test_type, type_targets} ->
      slide(
        Enum.sort_by(type_targets, & &1.timestamp, DateTime),
        Enum.sort_by(Map.get(pool_by_type, test_type, []), & &1.timestamp, DateTime),
        [],
        []
      )
    end)
    |> Map.new()
  end

  # Baseline pool for a list: eligible rows of the same test_types spanning each
  # row's prior window, in one query (a history page spans few rows, so this stays
  # small) - sorted ascending for the slide.
  defp baseline_pool([]), do: []

  defp baseline_pool(measurements) do
    test_types = measurements |> Enum.map(& &1.test_type) |> Enum.uniq()
    earliest = measurements |> Enum.min_by(& &1.timestamp, DateTime) |> Map.fetch!(:timestamp)
    latest = measurements |> Enum.max_by(& &1.timestamp, DateTime) |> Map.fetch!(:timestamp)
    since = DateTime.add(earliest, -@baseline_window_days * 24 * 3600, :second)

    from(m in Measurement,
      where:
        m.test_type in ^test_types and m.timestamp > ^since and m.timestamp <= ^latest and
          not m.failed and m.source != "manual",
      order_by: [asc: m.timestamp]
    )
    |> Repo.all()
  end

  # Two-pointer slide (targets + pool ascending, same test_type): the window holds
  # eligible pool rows with `timestamp ∈ (target − window, target)` - admit newer
  # rows, evict ones past the window as targets advance. Accumulates `{id, baseline}`.
  defp slide([], _pool, _window, acc), do: acc

  defp slide([target | rest], pool, window, acc) do
    {admitted, pool} =
      Enum.split_while(pool, fn m -> DateTime.compare(m.timestamp, target.timestamp) == :lt end)

    cutoff = DateTime.add(target.timestamp, -@baseline_window_days * 24 * 3600, :second)

    window =
      (window ++ admitted)
      |> Enum.drop_while(fn m -> DateTime.compare(m.timestamp, cutoff) != :gt end)

    slide(rest, pool, window, [{target.id, window_baseline(window)} | acc])
  end

  defp window_baseline(window) when length(window) < @baseline_min_samples, do: :insufficient

  defp window_baseline(window) do
    %{
      download: median(numbers(window, & &1.download_mbps)),
      upload: median(numbers(window, & &1.upload_mbps)),
      ping: median(numbers(window, & &1.ping_latency))
    }
  end

  defp numbers(rows, fun), do: for(row <- rows, is_number(fun.(row)), do: fun.(row))

  defp baseline_eligible?(%Measurement{failed: failed, source: source}),
    do: not failed and source != "manual"

  defp median([]), do: nil

  defp median(values) do
    sorted = Enum.sort(values)
    len = length(sorted)
    mid = div(len, 2)

    if rem(len, 2) == 1 do
      Enum.at(sorted, mid)
    else
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    end
  end

  defp day_bucket(%DateTime{} = ts) do
    DateTime.new!(DateTime.to_date(ts), ~T[00:00:00], "Etc/UTC")
  end

  defp maybe_require_download(query, promised) when promised > 0.0 do
    where(query, [m], m.download_mbps >= ^promised)
  end

  defp maybe_require_download(query, _promised), do: query

  defp maybe_require_upload(query, promised) when promised > 0.0 do
    where(query, [m], m.upload_mbps >= ^promised)
  end

  defp maybe_require_upload(query, _promised), do: query

  defp percent_of(_meeting, 0), do: nil
  defp percent_of(meeting, total), do: Float.round(meeting / total * 100, 1)

  defp apply_filters(query, filters) do
    query
    |> maybe_filter_date_from(filters["date_from"])
    |> maybe_filter_date_to(filters["date_to"])
    |> maybe_filter_outcome(filters["outcome"])
    |> maybe_filter_server(filters["server"])
  end

  defp maybe_filter_date_from(query, nil), do: query
  defp maybe_filter_date_from(query, ""), do: query

  defp maybe_filter_date_from(query, date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        datetime = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
        from(m in query, where: m.timestamp >= ^datetime)

      _ ->
        query
    end
  end

  defp maybe_filter_date_to(query, nil), do: query
  defp maybe_filter_date_to(query, ""), do: query

  defp maybe_filter_date_to(query, date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        datetime = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
        from(m in query, where: m.timestamp <= ^datetime)

      _ ->
        query
    end
  end

  # Outcome filters the persisted test result (did the run complete?), the only
  # SQL-able health signal now that the verdict is derived JIT. "succeeded" rows
  # still carry a JIT badge of `:healthy` or `:breach`; "failed" rows badge
  # `:failed` - so the filter and the badge never contradict each other.
  defp maybe_filter_outcome(query, nil), do: query
  defp maybe_filter_outcome(query, ""), do: query
  defp maybe_filter_outcome(query, "succeeded"), do: from(m in query, where: m.failed == false)
  defp maybe_filter_outcome(query, "failed"), do: from(m in query, where: m.failed == true)

  defp maybe_filter_server(query, nil), do: query
  defp maybe_filter_server(query, ""), do: query

  defp maybe_filter_server(query, server_name) do
    from(m in query, where: m.server_name == ^server_name)
  end

  defp maybe_filter_test_type(query, nil), do: query

  defp maybe_filter_test_type(query, test_type) do
    where(query, [m], m.test_type == ^test_type)
  end

  defp apply_sort(query, "download", dir) do
    order = if dir == "asc", do: :asc, else: :desc
    from(m in query, order_by: [{^order, m.download_mbps}])
  end

  defp apply_sort(query, "upload", dir) do
    order = if dir == "asc", do: :asc, else: :desc
    from(m in query, order_by: [{^order, m.upload_mbps}])
  end

  defp apply_sort(query, "latency", dir) do
    order = if dir == "asc", do: :asc, else: :desc
    from(m in query, order_by: [{^order, m.ping_latency}])
  end

  defp apply_sort(query, _field, dir) do
    order = if dir == "asc", do: :asc, else: :desc
    from(m in query, order_by: [{^order, m.timestamp}])
  end

  @doc "Get the IDs of the measurements adjacent to the given one (by timestamp)."
  def get_neighbor_ids(id) do
    m = get_measurement!(id)

    older =
      Repo.one(
        from(m2 in Measurement,
          where: m2.timestamp < ^m.timestamp,
          order_by: [desc: m2.timestamp],
          limit: 1,
          select: m2.id
        )
      )

    newer =
      Repo.one(
        from(m2 in Measurement,
          where: m2.timestamp > ^m.timestamp,
          order_by: [asc: m2.timestamp],
          limit: 1,
          select: m2.id
        )
      )

    %{older_id: older, newer_id: newer}
  end
end
