defmodule Baudflow.Measurements.Measurement do
  @moduledoc """
  Schema for speedtest measurement results.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :timestamp,
             :ping_latency,
             :ping_jitter,
             :ping_low,
             :ping_high,
             :download_bandwidth,
             :download_mbps,
             :download_bytes,
             :download_elapsed,
             :download_jitter,
             :upload_bandwidth,
             :upload_mbps,
             :upload_bytes,
             :upload_elapsed,
             :upload_jitter,
             :packet_loss,
             :isp,
             :server_id,
             :server_name,
             :server_location,
             :server_country,
             :server_host,
             :result_id,
             :result_url,
             :source,
             :speedtest_version,
             :healthy,
             :benchmarks,
             :schedule_id,
             :test_type,
             :failed,
             :inserted_at
           ]}

  schema "measurements" do
    field :timestamp, :utc_datetime
    # Ping
    field :ping_latency, :float
    field :ping_jitter, :float
    field :ping_low, :float
    field :ping_high, :float
    # Download
    field :download_bandwidth, :integer
    field :download_mbps, :float
    field :download_bytes, :integer
    field :download_elapsed, :integer
    field :download_jitter, :float
    # Upload
    field :upload_bandwidth, :integer
    field :upload_mbps, :float
    field :upload_bytes, :integer
    field :upload_elapsed, :integer
    field :upload_jitter, :float
    # Other
    field :packet_loss, :float
    field :isp, :string
    # Server
    field :server_id, :integer
    field :server_name, :string
    field :server_location, :string
    field :server_country, :string
    field :server_host, :string
    # Result
    field :result_id, :string
    field :result_url, :string
    # Provenance
    field :source, :string
    field :speedtest_version, :string
    # Health benchmarks
    field :healthy, :boolean
    field :benchmarks, :map
    # Raw
    field :raw_result, :map
    # Pipeline provenance (v2 forward-shape; writers land in slices 0b/0d)
    field :schedule_id, :id
    field :test_type, :string, default: "ookla"
    field :failed, :boolean, default: false

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc """
  Build a measurement changeset from a parsed test result (any TestRunner impl).

  Bandwidth is optional — a ping result has none, so its `download_mbps`/
  `upload_mbps` stay nil (and Postgres `avg()` then excludes it from speed
  averages). An Ookla result always carries bandwidth, so its mbps is derived.
  """
  def from_result(attrs) do
    attrs =
      attrs
      |> maybe_put_mbps(:download_bandwidth, :download_mbps)
      |> maybe_put_mbps(:upload_bandwidth, :upload_mbps)

    %__MODULE__{}
    |> cast(attrs, [
      :timestamp,
      :ping_latency,
      :ping_jitter,
      :ping_low,
      :ping_high,
      :download_bandwidth,
      :download_mbps,
      :download_bytes,
      :download_elapsed,
      :download_jitter,
      :upload_bandwidth,
      :upload_mbps,
      :upload_bytes,
      :upload_elapsed,
      :upload_jitter,
      :packet_loss,
      :isp,
      :server_id,
      :server_name,
      :server_location,
      :server_country,
      :server_host,
      :result_id,
      :result_url,
      :source,
      :speedtest_version,
      :healthy,
      :benchmarks,
      :raw_result,
      :schedule_id,
      :test_type,
      :failed
    ])
    |> validate_required([:timestamp, :ping_latency])
    |> unique_constraint(:result_id)
  end

  defp maybe_put_mbps(attrs, bandwidth_key, mbps_key) do
    case attrs[bandwidth_key] do
      nil -> attrs
      bandwidth -> Map.put(attrs, mbps_key, bandwidth * 0.000008)
    end
  end

  @doc "Changeset for a health/benchmark evaluation update."
  def health_changeset(measurement, attrs) do
    measurement
    |> cast(attrs, [:healthy, :benchmarks])
    |> validate_inclusion(:healthy, [true, false, nil])
  end
end
