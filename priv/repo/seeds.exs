# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# Default settings - will be upserted by the Settings context after slice 01.
# For now, record the expected defaults:
#
#   schedule_cron           → "0 * * * *"
#   server_id               → ""
#   retention_days          → "365"
#   dashboard_points        → "500"
