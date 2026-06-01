defmodule BaudFlowWeb.Router do
  use BaudFlowWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BaudFlowWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BaudFlowWeb do
    pipe_through :browser

    live "/", DashboardLive
    live "/history", HistoryLive
    live "/runs", RunsLive
    live "/results/:id", ResultLive
    live "/settings", SettingsLive
  end

  scope "/", BaudFlowWeb do
    pipe_through :api

    get "/health", HealthController, :check
  end
end
