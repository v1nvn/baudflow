defmodule BaudFlow.Settings.Setting do
  @moduledoc """
  Schema for application settings (key-value store).
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "settings" do
    field :key, :string
    field :value, :string

    timestamps()
  end

  @doc "Changeset for a setting."
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key, :value])
    |> unique_constraint(:key)
  end
end
