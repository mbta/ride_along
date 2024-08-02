defmodule RideAlong.AdeptTest do
  @moduledoc false
  use ExUnit.Case
  alias RideAlong.Adept
  alias RideAlong.AdeptFixtures

  @name __MODULE__

  setup do
    {:ok, _} = Adept.start_link(name: @name)

    :ok
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
