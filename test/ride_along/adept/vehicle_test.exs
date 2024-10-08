defmodule RideAlong.Adept.VehicleTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias RideAlong.Adept.Vehicle

  @route_id 2345
  @vehicle_id "5678"
  @map %{
    "RouteId" => @route_id,
    "VehicleId" => @vehicle_id,
    "Heading" => Decimal.new("90"),
    "Speed" => Decimal.new("15"),
    "Latitude" => Decimal.new("42.346"),
    "Longitude" => Decimal.new("-71.071"),
    "LocationDate" => {{2024, 10, 8}, {11, 6, 30, 0}},
    "LastPick" => nil,
    "LastDrop" => nil,
    "LastArrivedTrip" => nil,
    "LastDispatchArrivedTrip" => nil
  }
  describe "from_sql_map/1" do
    test "parses old-style map without pick/drop" do
      assert Vehicle.from_sql_map(@map) == %Vehicle{
               route_id: @route_id,
               vehicle_id: @vehicle_id,
               heading: Decimal.new("90"),
               speed: Decimal.new("15"),
               lat: Decimal.new("42.346"),
               lon: Decimal.new("-71.071"),
               timestamp: DateTime.from_naive!(~N[2024-10-08T11:06:30.000], "America/New_York"),
               last_pick: 1,
               last_drop: 1
             }
    end

    test "parses old-style map with pick/drop/arrival" do
      map = %{
        @map
        | "LastPick" => 5,
          "LastDrop" => 6,
          "LastArrivedTrip" => 100,
          "LastDispatchArrivedTrip" => 200
      }

      assert %Vehicle{
               last_pick: 5,
               last_drop: 6,
               last_arrived_trips: [100, 200]
             } = Vehicle.from_sql_map(map)
    end
  end
end
