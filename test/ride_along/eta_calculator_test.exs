defmodule RideAlong.EtaCalculatorTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias RideAlong.AdeptFixtures, as: Fixtures
  alias RideAlong.EtaCalculator
  alias RideAlong.OpenRouteService.Route

  describe "calculate/3" do
    setup do
      time =
        DateTime.shift_zone!(
          DateTime.utc_now(),
          Application.get_env(:ride_along, :time_zone)
        )

      five_before = DateTime.add(time, -5, :minute)
      five_after = DateTime.add(time, 5, :minute)

      {:ok,
       %{
         five_before: five_before,
         time: time,
         five_after: five_after
       }}
    end

    test "without a route, uses the pick_time", opts do
      trip = Fixtures.trip_fixture(%{promise_time: opts.five_before, pick_time: opts.time})

      assert EtaCalculator.calculate(trip, nil, nil) == opts.time
    end

    test "without a route, does not use a pick time if it's more than 5 minutes before the promise time",
         opts do
      trip = Fixtures.trip_fixture(%{promise_time: opts.five_after, pick_time: opts.five_before})

      assert EtaCalculator.calculate(trip, nil, nil) == opts.time
    end

    test "with route, uses the duration plus the vehicle timestamp, rounding up to the minute",
         opts do
      trip = Fixtures.trip_fixture(%{pick_time: opts.time, promise_time: opts.time})
      vehicle = Fixtures.vehicle_fixture()
      route = %Route{duration: 60.5}

      expected =
        vehicle.timestamp
        |> DateTime.add(2, :minute)
        |> Map.merge(%{second: 0, microsecond: {0, 0}})

      actual = EtaCalculator.calculate(trip, vehicle, route)

      diff =
        DateTime.diff(
          actual,
          expected,
          :second
        )

      assert diff >= 0
      assert diff <= 60

      # truncate to the minute
      assert %DateTime{second: 0, microsecond: {0, 0}} = actual
    end

    test "does not use an ETA more than 5 minutes before the promise time", opts do
      # vehicle should not arrive more than 5 minutes early
      trip = Fixtures.trip_fixture(%{promise_time: opts.five_after, pick_time: opts.five_after})
      vehicle = Fixtures.vehicle_fixture()
      route = %Route{duration: 0}

      assert EtaCalculator.calculate(trip, vehicle, route) == opts.five_after
    end
  end
end
