# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ride_along,
  time_zone: "America/New_York",
  generators: [timestamp_type: :utc_datetime],
  gzip_static_assets: false

# Configures the endpoint
config :ride_along, RideAlongWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: RideAlongWeb.ErrorHTML, json: RideAlongWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: RideAlong.PubSub,
  live_view: [signing_salt: "oH49ZB9T"]

config :ride_along, RideAlongWeb.PageController,
  redirect_to: "https://www.mbta.com/accessibility/the-ride"

config :ride_along, RideAlong.MqttConnection,
  broker_configs: [],
  broker_client_prefix: "ride_along"

config :ride_along, RideAlong.MqttListener, start: false

config :ride_along, RideAlong.SqlPublisher, start: false

config :ride_along, RideAlong.EtaMonitor, start: false

config :ride_along, RideAlong.OpenRouteService,
  duration_scale: 1.6,
  req_config: [
    base_url: "http://localhost:8082/"
  ]

config :ueberauth, Ueberauth,
  providers: [
    keycloak:
      {Ueberauth.Strategy.Oidcc,
       issuer: :keycloak_issuer,
       uid_field: "email",
       scopes: ~w(openid email roles),
       userinfo: true}
  ]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  ride_along: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.0",
  ride_along: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Use Tzdata for Elixir timezone actions
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
