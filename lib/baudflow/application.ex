defmodule Baudflow.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BaudflowWeb.Telemetry,
      Baudflow.Repo,
      # Seed the default schedule from the legacy cron setting on boot
      # (dev/prod). Gated off in test via :bootstrap_on_start so the schedules
      # table stays empty and tests own their state. :temporary restart - run
      # once; a seed failure must not crash the supervisor.
      {Task,
       fn ->
         if Application.get_env(:baudflow, :bootstrap_on_start, true),
           do: Baudflow.Scheduling.bootstrap()
       end},
      {Phoenix.PubSub, name: Baudflow.PubSub},
      {Oban, Application.fetch_env!(:baudflow, Oban)},
      BaudflowWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Baudflow.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BaudflowWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
