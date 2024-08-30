defmodule RideAlong.EtaCalculator do
  @moduledoc """
  Module to calculate the ETA, given some inputs:
  - trip
  - vehicle (optional)
  - OpenRouteService.Route (optional)
  """
  alias RideAlong.Adept.{Trip, Vehicle}
  alias RideAlong.OpenRouteService.Route

  @doc """
  Currently, the logic is:
  - if the current time is within 20 minutes of the promise time and we have a route:
    - take the latest of:
      - vehicle.timestamp + route.duration (truncated to the minute)
      - 5 minutes before the promise time
  - otherwise:
    - take the latest of:
      - pick time
      - 5 minutes before the promise time
  """
  @spec calculate(Trip.t(), Vehicle.t() | nil, Route.t() | nil, DateTime.t()) :: DateTime.t()
  def calculate(trip, vehicle, route, now)

  def calculate(%Trip{} = trip, vehicle, route, %DateTime{} = now)
      when (is_nil(vehicle) or is_struct(vehicle, Vehicle)) and
             (is_nil(route) or is_struct(route, Route)) do
    __MODULE__.Model.predict(trip, vehicle, route, now)
  end
end
