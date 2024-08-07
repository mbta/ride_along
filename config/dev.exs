import Config

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we can use it
# to bundle .js and .css sources.
config :ride_along, RideAlongWeb.Endpoint,
  https: [
    ip: {127, 0, 0, 1},
    port: 4001,
    cipher_suite: :strong,
    keyfile: "priv/cert/selfsigned_key.pem",
    certfile: "priv/cert/selfsigned.pem"
  ],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "UHZ0Lf/EGdIYNHWwTKoowoRJt+HFsrP8iwKPp/2XthQYE2BhRhjtfGJDLU0b70HI",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:ride_along, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:ride_along, ~w(--watch)]}
  ]

# Watch static and templates for browser reloading.
config :ride_along, RideAlongWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/ride_along_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :ride_along, RideAlongWeb.PageController, redirect_to: nil

config :ride_along, RideAlongWeb.Api,
  api_keys: %{
    "api_key" => "Local Development"
  }

config :ride_along, RideAlong.LinkShortener,
  secret: "UHZ0Lf/EGdIYNHWwTKoowoRJt+HFsrP8iwKPp/2XthQYE2BhRhjtfGJDLU0b70HI"

config :ride_along, RideAlong.MqttConnection,
  broker_configs: ["mqtt://system:manager@localhost/"],
  broker_topic_prefix: "ride-along-local/"

config :ride_along, RideAlong.MqttListener, start: true

config :ride_along, RideAlong.EtaMonitor, start: true

config :ride_along, RideAlong.RiderNotifier, start: true
# Enable dev routes for dashboard and mailbox
config :ride_along, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Include HEEx debug annotations as HTML comments in rendered markup
  debug_heex_annotations: true,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true
