defmodule RideAlong.EtaCalculator do
  @moduledoc """
  Module to calculate the ETA, given some inputs:
  - trip
  - vehicle (optional)
  - OpenRouteService.Route (optional)
  """
  alias RideAlong.Adept.{Trip, Vehicle}
  alias RideAlong.OpenRouteService.Route

  @use_pick_time_cutoff_s 60 * 20

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
  def calculate(trip, vehicle, route, now)

  def calculate(%Trip{} = trip, vehicle, route, %DateTime{} = now)
      when (is_nil(vehicle) or is_struct(vehicle, Vehicle)) and
             (is_nil(route) or is_struct(route, Route)) do
    earliest_arrival = naive_earliest_arrival(trip, vehicle, route)

    if DateTime.diff(trip.promise_time, now, :second) > @use_pick_time_cutoff_s or is_nil(route) do
      max_time([trip.pick_time, earliest_arrival])
    else
      earliest_arrival
    end
  end

  defp truncate_to_minute(dt) do
    Map.merge(dt, %{second: 0, microsecond: {0, 0}})
  end

  defp naive_earliest_arrival(trip, %Vehicle{} = vehicle, %Route{} = route) do
    duration_ms = trunc(route.duration * 1_000)

    ors_eta =
      vehicle.timestamp
      |> DateTime.add(duration_ms, :millisecond)
      |> truncate_to_minute()

    max_time([ors_eta, earliest_arrival(trip)])
  end

  defp naive_earliest_arrival(trip, _, _) do
    earliest_arrival(trip)
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
