defmodule Baudflow.Repo.Migrations.AddEscalatedCronToSchedules do
  use Ecto.Migration

  def change do
    alter table(:schedules) do
      # #13 adaptive testing: the cadence a schedule uses while escalated
      # (escalation_level > 0). Nullable — nil means "no adaptive speedup"
      # (escalation state is maintained but inert).
      add :escalated_cron, :string
    end
  end
end
