defmodule RideAlong.Adept.Trip do
  @moduledoc """
  Represents the Trip data coming from Adept.

  A Trip is a single pickup for a person.
  """
  @derive Jason.Encoder
  defstruct [
    :trip_id,
    :route_id,
    :date,
    :pick_time,
    :promise_time,
    :lat,
    :lon,
    :house_number,
    :address1,
    :address2,
    :city,
    :state,
    :zip,
    :pick_order,
    :drop_order,
    pickup_performed?: false,
    dropoff_performed?: false
  ]

  def from_sql_map(map) do
    %{
      "Id" => trip_id,
      "TripDate" => trip_date_time,
      "RouteId" => route_id,
      "PickTime" => pick_time,
      "PromiseTime" => promise_time,
      "PickHouseNumber" => house_number,
      "PickAddress1" => address1,
      "PickAddress2" => address2,
      "PickCity" => city,
      "PickSt" => state,
      "PickZip" => zip,
      "PickGridX" => grid_lon,
      "PickGridY" => grid_lat,
      "PickOrder" => pick_order,
      "DropOrder"=> drop_order,
      "PerformPickup" => perform_pickup,
      "PerformDropoff" => perform_dropoff
    } = map

    trip_date_time = RideAlong.SqlParser.local_timestamp(trip_date_time)

    %__MODULE__{
      trip_id: trip_id,
      route_id: route_id,
      date: DateTime.to_date(trip_date_time),
      pick_time: DateTime.add(trip_date_time, time_as_seconds_since_midnight(pick_time)),
      promise_time: DateTime.add(trip_date_time, time_as_seconds_since_midnight(promise_time)),
      lat: grid_to_decimal(grid_lat),
      lon: grid_to_decimal(grid_lon),
      house_number: house_number,
      address1: address1,
      address2: address2,
      city: city,
      state: state,
      zip: zip,
      pick_order: pick_order,
      drop_order: drop_order,
      pickup_performed?: perform_pickup != 0,
      dropoff_performed?: perform_dropoff != 0
    }
  end

  def address(%__MODULE__{} = trip) do
    street =
      [
        trip.house_number,
        trip.address1,
        trip.address2
      ]
      |> Enum.reject(&(&1 in ["", nil]))
      |> Enum.intersperse(" ")

    Enum.join(
      [
        street,
        trip.city,
        trip.state || "MA"
      ],
      ", "
    )
  end

  def compare(%__MODULE__{} = a, %__MODULE__{} = b) do
    date_compare = Date.compare(a.date, b.date)

    cond do
      date_compare != :eq ->
        date_compare

      a.trip_id < b.trip_id ->
        :lt

      a.trip_id > b.trip_id ->
        :gt

      true ->
        :eq
    end
  end

  @one_hundred_thousand Decimal.new(100_000)
  defp grid_to_decimal(integer) do
    integer
    |> Decimal.new()
    |> Decimal.div(@one_hundred_thousand)
  end

  defp time_as_seconds_since_midnight(time) do
    [hours, minutes] = String.split(time, ":", parts: 2)
    hours = String.to_integer(hours)
    minutes = String.to_integer(minutes)
    hours * 3_600 + minutes * 60
  end
end
