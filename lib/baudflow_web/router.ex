defmodule BaudflowWeb.Router do
  use BaudflowWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BaudflowWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BaudflowWeb do
    pipe_through :browser

    live "/", DashboardLive
    live "/history", HistoryLive
    live "/runs", RunsLive
    live "/results/:id", ResultLive
    live "/schedules", SchedulesLive, :index
    live "/schedules/new", SchedulesLive, :new
    live "/schedules/:id/edit", SchedulesLive, :edit
    live "/settings", SettingsLive
  end

  scope "/", BaudflowWeb do
    pipe_through :api

    get "/health", HealthController, :check
  end
end
