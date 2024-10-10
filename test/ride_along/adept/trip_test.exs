defmodule RideAlong.Adept.TripTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias RideAlong.Adept.Trip
  alias RideAlong.AdeptFixtures, as: Fixtures

  describe "from_sql_map/1" do
    test "parses a sample map" do
      time_zone = Application.get_env(:ride_along, :time_zone)

      sample = %{
        "Anchor" => "A",
        "Id" => 94_820_952,
        "PickAddress1" => "LUETTGEN VILLAGE",
        "PickAddress2" => "APT 152",
        "PickCity" => "CASPERTON",
        "PickGridX" => -7_106_166,
        "PickGridY" => 4_234_340,
        "PickHouseNumber" => "144",
        "PickSt" => "AK",
        "PickTime" => "3:33",
        "PickZip" => "50896",
        "PromiseTime" => "24:50",
        "RouteId" => 14_404,
        "ClientId" => 70_000,
        "ClientTripIndex" => 2,
        "TripDate" => {{2024, 05, 30}, {0, 0, 0, 0}},
        "Status" => "CX",
        "PickOrder" => 14,
        "DropOrder" => 16,
        "PerformPickup" => 2,
        "PerformDropoff" => 0,
        "LoadTime" => 7,
        "APtime1" => "00:00"
      }

      actual = Trip.from_sql_map(sample)

      expected = %Trip{
        trip_id: 94_820_952,
        route_id: 14_404,
        client_id: 70_000,
        date: ~D[2024-05-30],
        status: "CX",
        client_trip_index: 1,
        client_notification_preference: "NONE",
        pick_time: DateTime.new!(~D[2024-05-30], ~T[03:33:00], time_zone),
        promise_time: DateTime.new!(~D[2024-05-31], ~T[00:50:00], time_zone),
        pickup_arrival_time: nil,
        lat: Decimal.new("42.3434"),
        lon: Decimal.new("-71.06166"),
        house_number: "144",
        address1: "LUETTGEN VILLAGE",
        address2: "APT 152",
        city: "CASPERTON",
        state: "AK",
        zip: "50896",
        anchor: "A",
        pick_order: 14,
        drop_order: 16,
        load_time: 7,
        pickup_performed?: true,
        dropoff_performed?: false
      }

      assert actual == expected
    end
  end

  describe "status/3" do
    setup do
      now = DateTime.utc_now()
      trip = Fixtures.trip_fixture()
      vehicle = Fixtures.vehicle_fixture()
      {:ok, %{now: now, trip: trip, vehicle: vehicle}}
    end

    test "is :enroute for the default fixture", %{trip: trip, vehicle: vehicle, now: now} do
      assert Trip.status(trip, vehicle, now) == :enroute
    end

    test "is :closed if the trip was dropped off", %{vehicle: vehicle, now: now} do
      trip = Fixtures.trip_fixture(%{dropoff_performed?: true})

      assert Trip.status(trip, vehicle, now) == :closed
    end

    test "is :closed if the trip is more than an hour in the future", %{
      trip: trip,
      vehicle: vehicle,
      now: now
    } do
      now = DateTime.add(now, -61, :minute)

      assert Trip.status(trip, vehicle, now) == :closed
    end

    test "is :picked_up if the trip was picked up", %{vehicle: vehicle, now: now} do
      trip = Fixtures.trip_fixture(%{pickup_performed?: true})

      assert Trip.status(trip, vehicle, now) == :picked_up
    end

    test "is not :picked_up if the vehicle has performed a later drop off, but not this pickup index",
         %{
           trip: trip,
           now: now
         } do
      vehicle = Fixtures.vehicle_fixture(%{last_drop: trip.pick_order + 1})

      refute Trip.status(trip, vehicle, now) == :picked_up
    end

    test "is :arrived if the current trip is the last arrived trip", %{
      trip: trip,
      now: now
    } do
      vehicle = Fixtures.vehicle_fixture(%{last_arrived_trips: [trip.trip_id + 1, trip.trip_id]})

      assert Trip.status(trip, vehicle, now) == :arrived
    end

    test "is :arrived if the current trip has a pickup_arrival_time", %{
      trip: trip,
      vehicle: vehicle,
      now: now
    } do
      trip = %{trip | pickup_arrival_time: DateTime.utc_now()}

      assert Trip.status(trip, vehicle, now) == :arrived
    end

    test "is :enqueued if there is more than one pickup/dropoff before our pickup", %{
      trip: trip,
      now: now
    } do
      vehicle =
        Fixtures.vehicle_fixture(%{
          last_pick: trip.pick_order - 3,
          last_drop: trip.pick_order - 2
        })

      assert Trip.status(trip, vehicle, now) == :enqueued
    end

    test "is :enqueued if the pick_order is 0", %{trip: trip, vehicle: vehicle, now: now} do
      trip = %{trip | pick_order: 0, drop_order: 0}

      assert Trip.status(trip, nil, now) == :enqueued
      assert Trip.status(trip, vehicle, now) == :enqueued
    end

    test "is :enroute if there is exactly one pickup/dropoff before our pickup", %{
      trip: trip,
      now: now
    } do
      vehicle =
        Fixtures.vehicle_fixture(%{
          last_pick: trip.pick_order - 1,
          last_drop: trip.pick_order - 2
        })

      assert Trip.status(trip, vehicle, now) == :enroute
    end

    test "is :waiting if the pickup is next, but the vehicle is nearby and early", %{
      trip: trip,
      now: now
    } do
      vehicle =
        Fixtures.vehicle_fixture(%{lat: trip.lat, lon: trip.lon})

      assert Trip.status(trip, vehicle, now) == :waiting
    end

    test "is :enroute if the pickup is next, but the vehicle is nearby and moving", %{
      trip: trip,
      now: now
    } do
      vehicle =
        Fixtures.vehicle_fixture(%{lat: trip.lat, lon: trip.lon, speed: Decimal.new("10.0")})

      assert Trip.status(trip, vehicle, now) == :enroute
    end

    test "is :enroute if the pickup is next, but the vehicle is nearby and it's 5m before the promise time",
         %{
           trip: trip
         } do
      now = DateTime.add(trip.promise_time, -5, :minute)

      vehicle =
        Fixtures.vehicle_fixture(%{
          timestamp: now,
          lat: trip.lat,
          lon: trip.lon
        })

      assert Trip.status(trip, vehicle, now) == :enroute
    end
  end

  describe "address/1" do
    test "returns an binary for the trip" do
      check all(t <- trip()) do
        assert is_binary(Trip.address(t))
      end
    end

    test "includes the zip code if present" do
      trip = Fixtures.trip_fixture()

      assert Trip.address(trip) =~ trip.zip
    end
  end

  defp trip do
    gen all(
          house_number <- nullable_string(:ascii),
          address1 <- string(:ascii),
          address2 <- nullable_string(:ascii),
          city <- string(:ascii),
          state <- string(:ascii),
          zip <- nullable_string(:ascii)
        ) do
      %Trip{
        house_number: house_number,
        address1: address1,
        address2: address2,
        city: city,
        state: state,
        zip: zip
      }
    end
  end

  defp nullable_string(kind) do
    one_of([constant(nil), string(kind)])
  end
end
