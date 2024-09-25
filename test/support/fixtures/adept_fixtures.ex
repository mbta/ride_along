defmodule RideAlong.AdeptFixtures do
  @moduledoc """
  Test helpers for creating resources in the RideAlong.Adept context.
  """

  alias RideAlong.Adept.{Trip, Vehicle}

  @trip_id 1234
  @route_id 4567
  @vehicle_id "9876"

  @doc "Create a trip"
  def trip_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          trip_id: @trip_id,
          route_id: @route_id,
          client_id: 70_000,
          client_trip_index: 0,
          client_notification_preference: "TEXT ONLY",
          date: DateTime.to_date(local_timestamp(0, :second)),
          pick_time: local_timestamp(30, :minute),
          promise_time: local_timestamp(35, :minute),
          lat: Decimal.new("42.3434"),
          lon: Decimal.new("-71.06166"),
          house_number: "144",
          address1: "LUETTGEN VILLAGE",
          address2: "APT 152",
          city: "CASPERTON",
          state: "AK",
          zip: "50896",
          anchor: "P",
          pick_order: 5,
          drop_order: 7,
          load_time: 4
        },
        attrs
      )

    struct!(Trip, attrs)
  end

  @doc "Create a vehicle"
  def vehicle_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          route_id: @route_id,
          vehicle_id: @vehicle_id,
          lat: Decimal.new("42.35167"),
          lon: Decimal.new("-71.06694"),
          timestamp: local_timestamp(-1, :second),
          last_pick: 4,
          last_drop: 2,
          last_arrived_trips: []
        },
        attrs
      )

    struct!(Vehicle, attrs)
  end

  defp local_timestamp(add, unit) do
    DateTime.utc_now()
    |> Map.merge(%{second: 0, millisecond: {0, 0}})
    |> DateTime.add(add, unit)
    |> DateTime.shift_zone!(Application.get_env(:ride_along, :time_zone))
  end
end
