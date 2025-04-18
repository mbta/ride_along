defmodule RideAlong.EtaCalculator do
  @moduledoc """
  Module to calculate the ETA, given some inputs:
  - trip
  - vehicle (optional)
  - OpenRouteService.Route (optional)
  """
  alias RideAlong.Adept.Trip
  alias RideAlong.Adept.Vehicle
  alias RideAlong.OpenRouteService.Route

  require Logger

  @doc """
  Currently, we use a machine-learning model if the status is "enroute" or
  "waiting", and the pick time otherwise.
  """
  @spec calculate(Trip.t(), Vehicle.t() | nil, Route.t() | nil, DateTime.t()) ::
          DateTime.t() | nil
  def calculate(trip, vehicle, route, now)

  def calculate(%Trip{} = trip, vehicle, route, %DateTime{} = now)
      when (is_nil(vehicle) or is_struct(vehicle, Vehicle)) and (is_nil(route) or is_struct(route, Route)) do
    case Trip.status(trip, vehicle, now) do
      status when status in [:enroute, :waiting] ->
        try do
          predicted = __MODULE__.Model.predict(trip, vehicle, route, vehicle.timestamp)

          DateTime.shift_zone!(predicted, trip.promise_time.time_zone)
        rescue
          e ->
            Logger.error(
              "#{__MODULE__} error calculating trip_id=#{trip.trip_id} route=#{trip.route_id} promise=#{trip.promise_time} pick=#{trip.pick_time} error=#{inspect(e)}"
            )

            future_time(trip.pick_time, now)
        end

      :enqueued ->
        future_time(trip.pick_time, now)

      _ ->
        future_time(trip.pick_time, now)
    end
  end

  defp future_time(dt, now)
  defp future_time(nil, %DateTime{} = now), do: now
  defp future_time(%DateTime{} = dt, %DateTime{} = now), do: Enum.max([dt, now], DateTime)
end
