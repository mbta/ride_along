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
          end

        route =
          if has_vehicle? and duration do
            %Route{duration: duration * 60, distance: 1.0}
          end

        actual = EtaCalculator.calculate(trip, vehicle, route, @now)

        assert DateTime.compare(actual, @now) != :lt,
               "Assertion failed: predicted #{actual} is earlier than now #{@now}"

        if route do
          ors_eta = DateTime.add(@now, duration, :minute)

          assert DateTime.compare(actual, ors_eta) != :lt,
                 "Assertion failed: predicted #{actual} is earlier than OpenRouteService ETA #{ors_eta}"
        end
      end
    end

    test "returns the ETA in the same timezone as the promise time" do
      trip = Fixtures.trip_fixture(%{})
      vehicle = Fixtures.vehicle_fixture(%{})
      route = %Route{duration: 60, distance: 1.0}

      actual =
        EtaCalculator.calculate(
          trip,
          vehicle,
          route,
          DateTime.shift_zone!(trip.promise_time, "Etc/UTC")
        )

      assert actual.time_zone == trip.promise_time.time_zone
    end

    test "always returns the pick time if the trip is closed" do
      trip = Fixtures.trip_fixture()
      vehicle = Fixtures.vehicle_fixture(%{last_drop: trip.drop_order + 1})

      assert EtaCalculator.calculate(trip, vehicle, nil, @now) == trip.pick_time
    end

    test "returns a time even if the model crashes" do
      assert %DateTime{} =
               EtaCalculator.calculate(
                 Fixtures.trip_fixture(%{promise_time: nil}),
                 Fixtures.vehicle_fixture(),
                 %Route{duration: 60, distance: 1.0},
                 @now
               )
    end
  end
end
