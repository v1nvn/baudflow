defmodule BaudFlow.Repo.Migrations.CreateMeasurements do
  use Ecto.Migration

  def change do
    create table(:measurements) do
      add :timestamp, :utc_datetime, null: false
      # Ping
      add :ping_latency, :float
      add :ping_jitter, :float
      add :ping_low, :float
      add :ping_high, :float
      # Download
      add :download_bandwidth, :bigint
      add :download_mbps, :float
      add :download_bytes, :bigint
      add :download_elapsed, :integer
      add :download_jitter, :float
      # Upload
      add :upload_bandwidth, :bigint
      add :upload_mbps, :float
      add :upload_bytes, :bigint
      add :upload_elapsed, :integer
      add :upload_jitter, :float
      # Other
      add :packet_loss, :float
      add :isp, :string
      # Server
      add :server_id, :integer
      add :server_name, :string
      add :server_location, :string
      add :server_country, :string
      add :server_host, :string
      # Result
      add :result_id, :string
      add :result_url, :string
      # Provenance
      add :source, :string
      add :speedtest_version, :string
      # Raw
      add :raw_result, :map

      timestamps()
    end

    create index(:measurements, [:timestamp])
    create index(:measurements, [:server_id])
    create unique_index(:measurements, [:result_id])

    # GIN index on raw_result jsonb - enables ad-hoc queries on stored Ookla JSON
    execute "CREATE INDEX ON measurements USING gin(raw_result)"
  end
end
