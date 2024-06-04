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
    :anchor,
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
      "Anchor" => anchor,
      "PickOrder" => pick_order,
      "DropOrder" => drop_order,
      "PerformPickup" => perform_pickup,
      "PerformDropoff" => perform_dropoff
    } = map

    trip_date_time = RideAlong.SqlParser.local_timestamp(trip_date_time)

    %__MODULE__{
      trip_id: trip_id,
      route_id: route_id,
      date: DateTime.to_date(trip_date_time),
      pick_time: relative_time(pick_time, trip_date_time),
      promise_time: relative_time(promise_time, trip_date_time),
      lat: grid_to_decimal(grid_lat),
      lon: grid_to_decimal(grid_lon),
      house_number: house_number,
      address1: address1,
      address2: address2,
      city: city,
      state: state,
      zip: zip,
      anchor: anchor,
      pick_order: pick_order,
      drop_order: drop_order,
      pickup_performed?: perform_pickup != 0,
      dropoff_performed?: perform_dropoff != 0
    }
  end

  def status(
        %__MODULE__{} = trip,
        %RideAlong.Adept.Vehicle{} = vehicle,
        now \\ DateTime.utc_now()
      ) do
    hours_until_pick = DateTime.diff(trip.pick_time, now, :hour)

    cond do
      trip.dropoff_performed? ->
        :closed

      max(vehicle.last_pick, vehicle.last_drop) >= trip.drop_order ->
        :closed

      hours_until_pick > 0 ->
        :closed

      trip.pickup_performed? ->
        :picked_up

      max(vehicle.last_pick, vehicle.last_drop) >= trip.pick_order ->
        :picked_up

      trip.trip_id == vehicle.last_arrived_trip ->
        :arrived

      trip.pick_order - max(vehicle.last_pick, vehicle.last_drop) == 1 ->
        :enroute

      true ->
        :enqueued
    end
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
    date_compare =
      case {a.pick_time, b.pick_time} do
        {%DateTime{} = a_dt, %DateTime{} = b_dt} ->
          DateTime.compare(a_dt, b_dt)

        {%DateTime{}, _} ->
          :lt

        {_, %DateTime{}} ->
          :gt

        _ ->
          :eq
      end

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

  defp relative_time("", _date_time) do
    nil
  end

  defp relative_time(time, date_time) do
    [hours, minutes] = String.split(time, ":", parts: 2)
    hours = String.to_integer(hours)
    minutes = String.to_integer(minutes)

    # we start at noon to ensure the time is relative to the correct timezone during DST transitions
    noon =
      DateTime.new!(
        DateTime.to_date(date_time),
        ~T[12:00:00],
        date_time.time_zone
      )

    DateTime.add(noon, (hours - 12) * 60 + minutes, :minute)
  end
end
