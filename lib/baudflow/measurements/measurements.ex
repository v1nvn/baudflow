defmodule Baudflow.Measurements do
  @moduledoc """
  Context for speedtest measurement results.
  """
  import Ecto.Query
  alias Baudflow.Measurements.Measurement
  alias Baudflow.Repo

  @doc "Create a measurement from a parsed test-result attributes map."
  def create_measurement(attrs) do
    Measurement.from_result(attrs)
    |> Repo.insert()
  end

  @doc """
  Insert a measurement marking a failed test — no speed/ping data, just a
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

  Pass `test_type:` to scope to one impl — the dashboard uses `"ookla"` so ping
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

  @doc "Update healthy and benchmarks fields on a measurement."
  def update_health(measurement, healthy, benchmarks) do
    Measurement.health_changeset(measurement, %{healthy: healthy, benchmarks: benchmarks})
    |> Repo.update()
  end

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
    |> maybe_filter_healthy(filters["healthy"])
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

  defp maybe_filter_healthy(query, nil), do: query
  defp maybe_filter_healthy(query, ""), do: query
  defp maybe_filter_healthy(query, "healthy"), do: from(m in query, where: m.healthy == true)
  defp maybe_filter_healthy(query, "unhealthy"), do: from(m in query, where: m.healthy == false)

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
