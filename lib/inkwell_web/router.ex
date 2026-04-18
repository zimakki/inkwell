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

  # Other scopes may use custom stacks.
  # scope "/api", InkwellWeb do
  #   pipe_through :api
  # end
end
