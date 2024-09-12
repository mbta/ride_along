defmodule RideAlong.EtaCalculatorTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias RideAlong.AdeptFixtures, as: Fixtures
  alias RideAlong.EtaCalculator
  alias RideAlong.OpenRouteService.Route

  @now ~U[2024-08-27T12:00:00Z]

  describe "calculate/4" do
    test "never returns a time before now or the route duration" do
      check all(
              pick_offset <- integer(-15..30),
              promise_offset <- integer(-15..30),
              has_vehicle? <- boolean(),
              duration <- one_of([constant(nil), integer(0..5)])
            ) do
        promise_time = DateTime.add(@now, promise_offset, :minute)
        pick_time = DateTime.add(@now, pick_offset, :minute)
        trip = Fixtures.trip_fixture(%{promise_time: promise_time, pick_time: pick_time})

        vehicle =
          if has_vehicle? do
            Fixtures.vehicle_fixture(%{
              timestamp: @now
            })
          else
            nil
          end

        route =
          if duration do
            %Route{duration: duration * 60, distance: 1.0}
          else
            nil
          end

        actual = EtaCalculator.calculate(trip, vehicle, route, @now)

        assert DateTime.compare(actual, @now) != :lt,
               "Assertion failed: predicted #{actual} is earlier than now #{@now}"

        if duration do
          ors_eta = DateTime.add(@now, duration, :minute)

          assert DateTime.compare(actual, ors_eta) != :lt,
                 "Assertion failed: predicted #{actual} is earlier than OpenRouteService ETA #{ors_eta}"
        end
      end
    end
  end
end
