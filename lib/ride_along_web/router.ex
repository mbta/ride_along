defmodule RideAlongWeb.Router do
  use RideAlongWeb, :router

  pipeline :shared do
    plug Plug.SSL, host: nil, rewrite_on: [:x_forwarded_proto]
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RideAlongWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers_runtime, %{
      "content-security-policy" =>
        "default-src 'self'; img-src https://cdn.mbta.com data: 'self'; connect-src 'self' wss://$HOST"
    }
  end

  pipeline :preconnect_cdn do
    plug :preconnect, "https://cdn.mbta.com"
  end

  pipeline :api do
    plug RideAlongWeb.Api
    plug JSONAPI.EnsureSpec
    plug JSONAPI.UnderscoreParameters
  end

  pipeline :admin do
    plug RideAlongWeb.AuthManager, roles: ["admin"]
  end

  scope "/", RideAlongWeb do
    get "/_health", HealthController, :index
    post "/analytics", AnalyticsController, :create
  end

  scope "/", RideAlongWeb do
    pipe_through [:shared, :browser]

    get "/", PageController, :home
  end

  scope "/t", RideAlongWeb.TripLive do
    pipe_through [:shared, :browser, :preconnect_cdn]

    live "/:token", Show
  end

  scope "/api", RideAlongWeb.Api do
    pipe_through [:shared, :api]

    get("/trips/:trip_id", TripController, :show)
  end

  scope "/auth", RideAlongWeb do
    pipe_through [:shared, :browser]

    get "/logout", AuthController, :logout
    get "/:unused", AuthController, :request
    get "/:unused/callback", AuthController, :callback
  end

  scope "/admin", RideAlongWeb do
    pipe_through [:shared, :browser, :admin]

    live "/", AdminLive.Index
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:ride_along, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:shared, :browser]

      live "/trip/:trip", RideAlongWeb.TripLive.Show, :show
      live_dashboard "/dashboard", metrics: RideAlongWeb.Telemetry
    end
  end

  def put_secure_browser_headers_runtime(conn, params) do
    host =
      case conn.port do
        443 -> conn.host
        port -> "#{conn.host}:#{port}"
      end

    params =
      for {key, value} <- params, into: %{} do
        {key, String.replace(value, "$HOST", host)}
      end

    put_secure_browser_headers(conn, params)
  end

  def preconnect(conn, url) do
    put_resp_header(conn, "link", "<#{URI.encode(url)}>; rel=\"preconnect\"")
  end
end
