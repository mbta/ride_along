import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ride_along, RideAlongWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "j4HS1A9X2jrCQn8zLal1ivgnrqqjvyX1kJqUlCIkxrAVIrb6mTf9nfvh4xCmGFRV",
  server: false

config :ride_along, RideAlong.OpenRouteService,
  req_config: [
    plug: {Req.Test, RideAlong.OpenRouteService}
  ]

config :ride_along, RideAlong.EtaCalculator.Model, start: true

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true
