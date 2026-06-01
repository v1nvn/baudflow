defmodule BaudFlow.Repo.Migrations.CreateRuns do
  use Ecto.Migration

  def change do
    create table(:runs) do
      add :started_at, :utc_datetime, null: false
      add :completed_at, :utc_datetime
      add :status, :string, null: false
      add :error, :string
      add :oban_job_id, :integer
      add :measurement_id, references(:measurements, on_delete: :nilify_all)

      timestamps()
    end

    create index(:runs, [:started_at])
    create index(:runs, [:status])
    create index(:runs, [:oban_job_id])
  end
end
