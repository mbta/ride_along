defmodule RideAlong.EtaCalculator do
  @moduledoc """
  Module to calculate the ETA, given some inputs:
  - trip
  - vehicle (optional)
  - OpenRouteService.Route (optional)
  """
  require Logger

  alias RideAlong.Adept.{Trip, Vehicle}
  alias RideAlong.OpenRouteService.Route

  @doc """
  Currently, we use a machine-learning model if the status is "enroute" or
  "waiting", and the pick time otherwise.
  """
  @spec calculate(Trip.t(), Vehicle.t() | nil, Route.t() | nil, DateTime.t()) ::
          DateTime.t() | nil
  def calculate(trip, vehicle, route, now)

  def calculate(%Trip{} = trip, vehicle, route, %DateTime{} = now)
      when (is_nil(vehicle) or is_struct(vehicle, Vehicle)) and
             (is_nil(route) or is_struct(route, Route)) do
    case Trip.status(trip, vehicle, now) do
      status when status in [:enroute, :waiting] ->
        try do
          predicted = __MODULE__.Model.predict(trip, vehicle, route, now)

          DateTime.shift_zone!(predicted, trip.promise_time.time_zone)
        rescue
          e ->
            Logger.error(
              "#{__MODULE__} error calculating trip_id=#{trip.trip_id} route=#{trip.route_id} promise=#{trip.promise_time} pick=#{trip.pick_time} error=#{inspect(e)}"
            )

            trip.pick_time
        end

      :enqueued ->
        Enum.max([trip.pick_time, now], DateTime)

      _ ->
        trip.pick_time
    end
  end
end
