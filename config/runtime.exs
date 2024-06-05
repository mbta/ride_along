import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/ride_along start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :ride_along, RideAlongWeb.Endpoint, server: true

  config :ride_along, RideAlong.MqttListener, start: true

  config :ride_along, RideAlong.EtaMonitor, start: true
end

if System.get_env("SQLCMDSERVER") != nil and config_env() != :test do
  config :ride_along, RideAlong.SqlPublisher,
    database: [
      hostname: System.fetch_env!("SQLCMDSERVER"),
      port: 1433,
      username: System.get_env("SQLCMDUSER") || "",
      password: System.get_env("SQLCMDPASSWORD") || "",
      database: "ADEPT6_GCS"
    ],
    start: true
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :ride_along, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :ride_along, RideAlong.OpenRouteService,
    req_config: [
      base_url: System.get_env("ORS_BASE_URL")
    ]

  config :ride_along, RideAlong.LinkShortener, secret: secret_key_base

  config :ride_along, RideAlongWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port,
      http_options: [
        log_protocol_errors: false
      ]
    ],
    secret_key_base: secret_key_base

  mqtt_url = System.get_env("MQTT_BROKER_URL")

  if mqtt_url not in [nil, ""] do
    topic_prefix = System.get_env("MQTT_TOPIC_PREFIX", "")
    username = System.get_env("MQTT_BROKER_USERNAME")

    passwords =
      case System.get_env("MQTT_BROKER_PASSWORD") do
        nil -> [nil]
        "" -> [nil]
        passwords -> String.split(passwords, " ")
      end

    configs =
      for url <- String.split(mqtt_url, " "),
          password <- passwords do
        EmqttFailover.Config.from_url(url, username: username, password: password)
      end

    config :ride_along, RideAlong.MqttConnection,
      broker_configs: configs,
      broker_topic_prefix: topic_prefix
  end
end

if issuer = System.get_env("KEYCLOAK_ISSUER") do
  config :ueberauth_oidcc,
    issuers: [
      %{name: :keycloak_issuer, issuer: issuer}
    ],
    providers: [
      keycloak: [
        client_id: System.get_env("KEYCLOAK_CLIENT_ID"),
        client_secret: System.get_env("KEYCLOAK_CLIENT_SECRET")
      ]
    ]
end
