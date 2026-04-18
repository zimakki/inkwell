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

    live_session :shell, layout: {InkwellWeb.Layouts, :app} do
      live "/", EmptyLive, :index
      live "/browse", BrowseLive, :index
    end
  end

  scope "/", InkwellWeb do
    pipe_through :api

    get "/health", HealthController, :show
    get "/status", HealthController, :status
    post "/stop", StopController, :stop
    get "/pick-file", FileDialogController, :file
    get "/pick-directory", FileDialogController, :directory
  end
end
