defmodule RideAlong.AdeptTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias RideAlong.Adept
  alias RideAlong.AdeptFixtures

  @name __MODULE__

  setup do
    {:ok, _} = Adept.start_link(name: @name)

    :ok
  end

  describe "set_trips/2" do
    test "can unset trips" do
      %{trip_id: trip_id} = trip = AdeptFixtures.trip_fixture()
      Adept.set_trips(@name, [trip])
      assert [%Adept.Trip{trip_id: ^trip_id}] = Adept.all_trips(@name)
      assert %Adept.Trip{trip_id: ^trip_id} = Adept.get_trip(@name, trip_id)
      assert Adept.all_trips_count(@name) == 1

      Adept.set_trips(@name, [])
      assert Adept.all_trips(@name) == []
      assert Adept.get_trip(@name, trip_id) == nil
    end
  end

  describe "set_vehicles/2" do
    test "can unset the vehicles" do
      vehicle = AdeptFixtures.vehicle_fixture()
      Adept.set_vehicles(@name, [vehicle])
      Adept.set_vehicles(@name, [])

      refute Adept.get_vehicle_by_route(@name, vehicle.route_id)
    end
  end
end
