defmodule RideAlong.Adept.Trip do
  @moduledoc """
  Represents the Trip data coming from Adept.

  A Trip is a single pickup for a person.
  """

  alias RideAlong.Adept.Vehicle

  @derive Jason.Encoder
  defstruct [
    :trip_id,
    :route_id,
    :client_id,
    :date,
    :status,
    :pick_time,
    :promise_time,
    :pickup_arrival_time,
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
    :load_time,
    :client_notification_preference,
    client_trip_index: 0,
    pickup_performed?: false,
    dropoff_performed?: false
  ]

  @type id :: integer()
  @type t :: %__MODULE__{
          trip_id: id(),
          pick_time: DateTime.t() | nil,
          promise_time: DateTime.t() | nil
        }

  @type status :: :closed | :enqueued | :enroute | :waiting | :arrived | :picked_up

  @spec from_sql_map(%{binary() => term()}) :: t()
  def from_sql_map(map) do
    %{
      "Id" => trip_id,
      "TripDate" => {{year, month, day}, _},
      "RouteId" => route_id,
      "ClientId" => client_id,
      "ClientTripIndex" => client_trip_index,
      "Status" => status,
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
      "PerformDropoff" => perform_dropoff,
      "LoadTime" => load_time,
      "APtime1" => pickup_arrival_time
    } = map

    trip_date = Date.new!(year, month, day)

    %__MODULE__{
      trip_id: trip_id,
      route_id: route_id,
      client_id: client_id,
      client_trip_index: client_trip_index - 1,
      # can move this to the pattern match once the MQTT data has updated. -ps
      client_notification_preference: map["ClientNotificationPreference"],
      date: trip_date,
      status: status,
      pick_time: relative_time(pick_time, trip_date),
      promise_time: relative_time(promise_time, trip_date),
      pickup_arrival_time: relative_time(pickup_arrival_time, trip_date),
      lat: grid_to_decimal(grid_lat),
      lon: grid_to_decimal(grid_lon),
      house_number: house_number,
      address1: address1,
      address2: address2,
      city: city,
      state: state || "MA",
      zip: zip,
      anchor: anchor,
      pick_order: pick_order,
      drop_order: drop_order,
      pickup_performed?: perform_pickup != 0,
      dropoff_performed?: perform_dropoff != 0,
      load_time: load_time
    }
  end

  @spec status(t(), Vehicle.t() | nil, DateTime.t()) :: status()
  def status(trip, vehicle, now \\ DateTime.utc_now())

  def status(%__MODULE__{status: status}, _vehicle, _now) when status != "S" do
    :closed
  end

  def status(%__MODULE__{dropoff_performed?: true}, _vehicle, _now) do
    :closed
  end

  def status(%__MODULE__{pickup_performed?: true}, _vehicle, _now) do
    :picked_up
  end

  def status(%__MODULE__{pickup_arrival_time: %DateTime{}}, _vehicle, _now) do
    :arrived
  end

  def status(
        %__MODULE__{} = trip,
        %Vehicle{} = vehicle,
        %DateTime{} = now
      ) do
    minutes_remaining = minutes_until(trip, now)

    cond do
      minutes_remaining > {:ok, 59} ->
        :closed

      trip.pick_order == 0 ->
        :enqueued

      trip.trip_id in vehicle.last_arrived_trips ->
        :arrived

      trip.pick_order - max(vehicle.last_pick, vehicle.last_drop) <= 1 ->
        enroute_or_waiting_status(trip, vehicle, minutes_remaining)

      true ->
        :enqueued
    end
  end

  def status(%__MODULE__{} = trip, nil, %DateTime{} = now) do
    if minutes_until(trip, now) > {:ok, 59} do
      :closed
    else
      :enqueued
    end
  end

  @max_waiting_speed Decimal.new("5.0")

  defp enroute_or_waiting_status(trip, vehicle, minutes_remaining) do
    distance =
      :vincenty.distance(
        {Decimal.to_float(vehicle.lat), Decimal.to_float(vehicle.lon)},
        {Decimal.to_float(trip.lat), Decimal.to_float(trip.lon)}
      )

    if distance < 0.5 and not Decimal.gt?(vehicle.speed, @max_waiting_speed) and
         minutes_remaining > {:ok, 5} do
      :waiting
    else
      :enroute
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

    state_zip =
      if trip.zip do
        [trip.state, " ", trip.zip]
      else
        trip.state
      end

    Enum.join(
      [
        street,
        trip.city,
        state_zip
      ],
      ", "
    )
  end

  def compare(%__MODULE__{} = a, %__MODULE__{} = b) do
    cond do
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

  defp relative_time("00:00", _date_time) do
    nil
  end

  defp relative_time(time, date, time_zone \\ Application.get_env(:ride_along, :time_zone)) do
    [hours, minutes] = String.split(time, ":", parts: 2)
    hours = String.to_integer(hours)
    minutes = String.to_integer(minutes)

    noon =
      DateTime.new!(
        date,
        ~T[12:00:00],
        time_zone
      )

    DateTime.add(noon, (hours - 12) * 60 + minutes, :minute)
  end

  @spec minutes_until(t(), DateTime.t()) :: {:ok, integer()} | :unknown
  def minutes_until(%__MODULE__{promise_time: nil}, _now), do: :unknown

  def minutes_until(%__MODULE__{promise_time: time}, now),
    do: {:ok, DateTime.diff(time, now, :minute)}
end
