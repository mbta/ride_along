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
  Currently, we use a machine-learning model if the status is "enroute" or
  "waiting", and the pick time otherwise.
  """
  @spec calculate(Trip.t(), Vehicle.t() | nil, Route.t() | nil, DateTime.t()) :: DateTime.t()
  def calculate(trip, vehicle, route, now)

  def calculate(%Trip{} = trip, vehicle, route, %DateTime{} = now)
      when (is_nil(vehicle) or is_struct(vehicle, Vehicle)) and
             (is_nil(route) or is_struct(route, Route)) do
    case Trip.status(trip, vehicle, now) do
      status when status in [:enroute, :waiting] ->
        __MODULE__.Model.predict(trip, vehicle, route, now)

      :enqueued ->
        Enum.max([trip.pick_time, now], DateTime)

      _ ->
        trip.pick_time
    end
  end
end
