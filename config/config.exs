# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :baudflow,
  ecto_repos: [Baudflow.Repo],
  generators: [timestamp_type: :utc_datetime]

# Oban base config: repo for all envs. Queues + crontab are identical in dev and
# prod, so they live here once (guarded out of :test, where Oban runs in
# testing: :manual and needs neither). runtime.exs adds only env-driven wiring.
config :baudflow, Oban, repo: Baudflow.Repo

if config_env() != :test do
  config :baudflow, Oban,
    queues: [scheduler: 1, speedtest: 1, notifications: 1, default: 1],
    plugins: [
      {Oban.Plugins.Cron,
       crontab: [
         {"* * * * *", Baudflow.Measurements.SchedulerWorker},
         {"0 3 * * *", Baudflow.Measurements.CleanupWorker}
       ]}
    ]
end

# Configure the endpoint
config :baudflow, BaudflowWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BaudflowWeb.ErrorHTML, json: BaudflowWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Baudflow.PubSub,
  live_view: [signing_salt: "UptEh1EU"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  baudflow: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --external:phoenix-colocated/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  baudflow: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Automated versioning (conventional commits → changelog → tag)
config :git_ops,
  mix_project: Baudflow.MixProject,
  changelog_file: "CHANGELOG.md",
  repository_url: "https://github.com/v1nvn/baudflow",
  manage_mix_version?: true,
  manage_readme_version: false,
  version_tag_prefix: "v"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
