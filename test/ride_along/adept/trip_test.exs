defmodule RideAlong.Adept.TripTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias RideAlong.Adept.Trip

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
        "TripDate" => {{2024, 05, 30}, {0, 0, 0, 0}},
        "PickOrder" => 14,
        "DropOrder" => 16,
        "PerformPickup" => 2,
        "PerformDropoff" => 0
      }

      actual = Trip.from_sql_map(sample)

      expected = %Trip{
        trip_id: 94_820_952,
        route_id: 14_404,
        date: ~D[2024-05-30],
        pick_time: DateTime.new!(~D[2024-05-30], ~T[03:33:00], time_zone),
        promise_time: DateTime.new!(~D[2024-05-31], ~T[00:50:00], time_zone),
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
        pickup_performed?: true,
        dropoff_performed?: false
      }

      assert actual == expected
    end
  end

  describe "address/1" do
    test "returns an binary for the trip" do
      check all(t <- trip()) do
        assert is_binary(Trip.address(t))
      end
    end
  end

  defp trip do
    gen all(
          house_number <- nullable_string(:ascii),
          address1 <- string(:ascii),
          address2 <- nullable_string(:ascii),
          city <- string(:ascii),
          state <- nullable_string(:ascii),
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
