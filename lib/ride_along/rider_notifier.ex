defmodule RideAlong.RiderNotifier do
  @moduledoc """
  Server which listens for updated trips and notifies the user about them.

  Currently, the rider is notified at the first of two events:
  - they are the next pickup for the vehicle
  - it is 30 minutes before the promise time

  We keep track locally of which events have been notified. This prevents trival
  re-notifications, but isn't resilient about restarting the server. We rely on
  the consumer of the notifications to de-duplicate them in those situations.
  """
  use GenServer
  require Logger

  alias RideAlong.Adept.Trip

  @default_name __MODULE__

  def start_link(opts) do
    if opts[:start] do
      name = Keyword.get(opts, :name, @default_name)
      GenServer.start_link(__MODULE__, [], name: name)
    else
      :ignore
    end
  end

  defstruct notified_trips: MapSet.new()
  @impl GenServer
  def init(_opts) do
    state = %__MODULE__{}
    Phoenix.PubSub.subscribe(RideAlong.PubSub, "trips:updated")
    Phoenix.PubSub.subscribe(RideAlong.PubSub, "vehicles:updated")
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:trips_updated, state) do
    state = update_trips(state)
    {:noreply, state}
  end

  def handle_info(:vehicles_updated, state) do
    state = update_trips(state)
    {:noreply, state}
  end

  def update_trips(state) do
    all_trips = RideAlong.Adept.all_trips()

    all_trips
    |> relevant_trips(DateTime.utc_now())
    |> Enum.reduce(state, &maybe_notify/2)
    |> cleanup_old_notifications(all_trips)
  end

  defp relevant_trips(all_trips, now) do
    # status is enroute/waiting (they're the next pickup) or diff is less than
    # 30m
    for trip <- all_trips,
        trip.pick_time != nil,
        trip.route_id > 0,
        not trip.pickup_performed?,
        diff = DateTime.diff(trip.promise_time, now),
        # we use a loop here to ensure we always set vehicle, even when it's nil
        vehicle <- [RideAlong.Adept.get_vehicle_by_route(trip.route_id)],
        diff < 1800 or
          Trip.status(trip, vehicle, now) in [:enroute, :waiting, :arrived] do
      trip
    end
  end

  defp maybe_notify(trip, state) do
    if MapSet.member?(state.notified_trips, trip.trip_id) do
      state
    else
      send_notification(state, trip)
    end
  end

  defp send_notification(state, trip) do
    Phoenix.PubSub.local_broadcast(
      RideAlong.PubSub,
      "notification:trip",
      {:trip_notification, trip}
    )

    %{state | notified_trips: MapSet.put(state.notified_trips, trip.trip_id)}
  end

  defp cleanup_old_notifications(state, all_trips) do
    # only keep trip IDs which are still in the `all_trips` list
    trip_ids = MapSet.new(all_trips, & &1.trip_id)
    %{state | notified_trips: MapSet.intersection(state.notified_trips, trip_ids)}
  end
end
