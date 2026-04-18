defmodule InkwellWeb.Router do
  use InkwellWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {InkwellWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", InkwellWeb do
    pipe_through :browser
  end

  scope "/", InkwellWeb do
    pipe_through :api

    get "/health", HealthController, :show
    get "/status", HealthController, :status
    post "/stop", StopController, :stop
  end
end
