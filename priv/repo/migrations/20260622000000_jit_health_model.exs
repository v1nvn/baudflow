defmodule Baudflow.Repo.Migrations.JitHealthModel do
  use Ecto.Migration

  # The health verdict moves from a stored column to a just-in-time derivation
  # (one value, one meaning — see `Baudflow.Measurements.health/1`). Two schema
  # changes follow from that:
  #
  #   * schedules/settings `threshold_enabled` (boolean) → `threshold_mode`
  #     (auto | absolute | off) — the boolean plus a new "auto" concept would be
  #     a compensating flag, so the column is replaced outright.
  #   * measurements `healthy` (the stored verdict) is dropped — nothing writes
  #     or reads it now; the per-check `benchmarks` snapshot stays (notifications
  #     render it at alert time).
  #
  # `change/0` (not `up/0`) so the reverse SQL in each `execute/2` and the typed
  # column re-adds make `mix ecto.rollback` work.

  def change do
    # --- measurements: drop the stored verdict ---------------------------------
    alter table(:measurements) do
      remove :healthy, :boolean
    end

    # --- schedules: per-row threshold_enabled → threshold_mode -----------------
    alter table(:schedules) do
      add :threshold_mode, :string
    end

    # An explicitly-enabled schedule kept absolute thresholds; an explicit false
    # stays off. nil (the common case — never set via UI) inherits the global.
    execute "UPDATE schedules SET threshold_mode = 'absolute' WHERE threshold_enabled = true",
            "UPDATE schedules SET threshold_mode = NULL WHERE threshold_mode = 'absolute'"

    execute "UPDATE schedules SET threshold_mode = 'off' WHERE threshold_enabled = false",
            "UPDATE schedules SET threshold_mode = NULL WHERE threshold_mode = 'off'"

    alter table(:schedules) do
      remove :threshold_enabled, :boolean
    end

    # --- settings: stored threshold_enabled → threshold_mode -------------------
    # The settings form persisted threshold_enabled on every save, so a stored
    # "false" is almost always the inert default incidentally written — not an
    # explicit "off" choice. Map an explicit "true" → "absolute" (preserve a
    # configured power-user setup) and delete the rest so those installs inherit
    # the new "auto" default rather than being locked into the broken old one.
    execute "INSERT INTO settings (key, value, inserted_at, updated_at) " <>
              "SELECT 'threshold_mode', 'absolute', NOW(), NOW() " <>
              "FROM settings WHERE key = 'threshold_enabled' AND value = 'true' " <>
              "ON CONFLICT (key) DO NOTHING",
            "DELETE FROM settings WHERE key = 'threshold_mode'"

    execute "DELETE FROM settings WHERE key = 'threshold_enabled'",
            "INSERT INTO settings (key, value, inserted_at, updated_at) " <>
              "VALUES ('threshold_enabled', 'false', NOW(), NOW())"
  end
end
