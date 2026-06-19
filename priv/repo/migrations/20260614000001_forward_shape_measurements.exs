defmodule Baudflow.Repo.Migrations.ForwardShapeMeasurements do
  use Ecto.Migration

  def change do
    alter table(:measurements) do
      # schedule_id is nullable until the runner is wired (slice 0b/0d); existing
      # rows and out-of-pipeline tests stay nil.
      add :schedule_id, references(:schedules, on_delete: :nilify_all)
      add :test_type, :string, default: "ookla", null: false
      add :failed, :boolean, default: false, null: false
    end

    create index(:measurements, [:schedule_id])
  end
end
