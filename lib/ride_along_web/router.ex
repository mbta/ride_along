defmodule RideAlongWeb.Router do
  use RideAlongWeb, :router

  pipeline :browser do
    plug Plug.SSL, host: nil, rewrite_on: [:x_forwarded_proto]
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RideAlongWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" => "default-src 'self'; img-src https://cdn.mbta.com data: 'self'"
    }
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", RideAlongWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/t/:token", TripLive.Show
  end

  scope "/", RideAlongWeb do
    get "/_health", HealthController, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", RideAlongWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:ride_along, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live "/trip/:trip", RideAlongWeb.TripLive.Show, :show
      live_dashboard "/dashboard", metrics: RideAlongWeb.Telemetry
    end
  end
end
