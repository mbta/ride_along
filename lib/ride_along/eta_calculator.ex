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
  Currently, the logic is to take the latest of:
  - pick time
  - vehicle.timestamp + route.duration (rounded up to the next minute)
  - 5 minutes before the promise time
  """
  def calculate(trip, vehicle, route)

  def calculate(%Trip{} = trip, %Vehicle{} = vehicle, %Route{} = route) do
    duration_ms = trunc(route.duration * 1_000)

    ors_eta =
      vehicle.timestamp
      |> DateTime.add(duration_ms, :millisecond)
      |> round_up_to_minute()

    max_time([ors_eta, calculate(trip, nil, nil)])
  end

  def calculate(%Trip{} = trip, _vehicle, _trip) do
    max_time([
      trip.pick_time,
      earliest_arrival(trip)
    ])
  end

  defp round_up_to_minute(%DateTime{second: second, microsecond: {microsecond, _precision}} = dt)
       when second > 0 or microsecond > 0 do
    dt
    |> DateTime.add(1, :minute)
    |> Map.merge(%{second: 0, microsecond: {0, 0}})
  end

  defp round_up_to_minute(dt) do
    dt
  end

  defp earliest_arrival(trip) do
    # SOP is that the vehicle should not arrive more than 5 minutes before the
    # promise time
    DateTime.add(trip.promise_time, -5, :minute)
  end

  defp max_time(times) do
    Enum.max(times, DateTime)
  end
end
