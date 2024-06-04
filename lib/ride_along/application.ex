defmodule RideAlong.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RideAlongWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:ride_along, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: RideAlong.PubSub},
      RideAlong.Adept,
      RideAlong.LinkShortener,
      {RideAlong.SqlPublisher, Application.get_env(:ride_along, RideAlong.SqlPublisher)},
      {RideAlong.MqttListener, Application.get_env(:ride_along, RideAlong.MqttListener)},
      {RideAlong.EtaMonitor, Application.get_env(:ride_along, RideAlong.EtaMonitor)},
      RideAlongWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RideAlong.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RideAlongWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
