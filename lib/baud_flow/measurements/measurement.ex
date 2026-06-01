defmodule BaudFlow.Measurements.Measurement do
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

    timestamps()
  end

  @doc "Changeset from Ookla CLI JSON output"
  def from_ookla_json(attrs) do
    download_bw = attrs[:download_bandwidth] || 0
    upload_bw = attrs[:upload_bandwidth] || 0

    attrs =
      attrs
      |> Map.put(:download_mbps, download_bw * 0.000008)
      |> Map.put(:upload_mbps, upload_bw * 0.000008)

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
      :raw_result
    ])
    |> validate_required([:timestamp, :ping_latency, :download_bandwidth, :upload_bandwidth])
    |> unique_constraint(:result_id)
  end
end
