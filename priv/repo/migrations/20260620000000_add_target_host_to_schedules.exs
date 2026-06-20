defmodule Baudflow.Repo.Migrations.AddTargetHostToSchedules do
  use Ecto.Migration

  def change do
    alter table(:schedules) do
      add :target_host, :string
    end
  end
end
