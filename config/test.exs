import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :baud_flow, BaudFlow.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "baud_flow_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :baud_flow, BaudFlowWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Hyl9WEY4hyTm5h/cAI9F1Dk44o4sNRPpGst2SQGbQIaurl421LBDVlfiPWWOhzTA",
  server: false

# Don't run any speedtests/cron during tests - enqueue and assert instead.
config :baud_flow, Oban, testing: :manual

# Point SpeedtestWorker at a deterministic fake CLI (see test/support/fake_speedtest)
config :baud_flow, :speedtest_bin, Path.expand("../test/support/fake_speedtest", __DIR__)

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
