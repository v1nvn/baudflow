defmodule Baudflow.Repo.Migrations.AddHealthToMeasurements do
  use Ecto.Migration

  def change do
    alter table(:measurements) do
      add :healthy, :boolean
      add :benchmarks, :map
    end
  end
end
