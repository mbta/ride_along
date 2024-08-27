defmodule RideAlong.EtaCalculatorTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias RideAlong.AdeptFixtures, as: Fixtures
  alias RideAlong.EtaCalculator
  alias RideAlong.OpenRouteService.Route

  @now ~U[2024-08-27T12:00:00Z]

  describe "calculate/4" do
    for {name, pick_offset, promise_offset, timestamp_offset, duration, expected_offset} <- [
          {"more than 20m before the promise time, uses the pick time if it's later", 30, 25, 0,
           5, 30},
          {"more than 20m before the promise time, uses the vehicle if it's later", 30, 25, 0, 40,
           40},
          {"more than 20m before the promise time, uses 5 minutes before the promise time if it's later",
           10, 25, 0, 5, 20},
          {"less than 20m before the promise time, uses the vehicle if it's later", 30, 15, 0, 15,
           15},
          {"less than 20m before the promise time, uses 5 minutes before the promise time if it's later",
           30, 15, 0, 5, 10},
          {"less than 20m before the promise time, uses the pick time if it's later and there's no vehicle",
           30, 15, nil, nil, 30}
        ] do
      test name do
        promise_time = DateTime.add(@now, unquote(promise_offset) * 60)
        pick_time = DateTime.add(@now, unquote(pick_offset) * 60)
        trip = Fixtures.trip_fixture(%{promise_time: promise_time, pick_time: pick_time})

        vehicle =
          if unquote(timestamp_offset) do
            Fixtures.vehicle_fixture(%{
              timestamp: DateTime.add(@now, unquote(timestamp_offset) * 60)
            })
          else
            nil
          end

        route =
          if unquote(duration) do
            %Route{duration: unquote(duration) * 60}
          else
            nil
          end

        expected = DateTime.add(@now, unquote(expected_offset) * 60)
        actual = EtaCalculator.calculate(trip, vehicle, route, @now)

        assert actual == expected
      end
    end
  end
end
