defmodule Baudflow.Repo.Migrations.CreateSchedules do
  use Ecto.Migration

  def change do
    create table(:schedules) do
      add :name, :string, null: false
      add :cron, :string, null: false
      add :server_id, :integer
      add :test_type, :string, default: "ookla", null: false
      add :enabled, :boolean, default: true, null: false
      add :escalation_level, :integer, default: 0, null: false
      add :breach_streak, :integer, default: 0, null: false
      add :threshold_enabled, :boolean
      add :download, :float
      add :upload, :float
      add :ping, :float

      timestamps()
    end

    create index(:schedules, [:enabled])
  end
end
