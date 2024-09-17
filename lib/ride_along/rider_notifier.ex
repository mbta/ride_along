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
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      :ignore
    end
  end

  defstruct notified_trips: MapSet.new(), client_ids: :all
  @impl GenServer
  def init(opts) do
    state = struct(__MODULE__, opts)
    RideAlong.PubSub.subscribe("trips:updated")
    RideAlong.PubSub.subscribe("vehicle:all")
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:trips_updated, state) do
    trips = RideAlong.Adept.all_trips()

    state =
      state
      |> update_trips(trips)
      |> cleanup_old_notifications(trips)

    {:noreply, state}
  end

  def handle_info({:vehicle_updated, v}, state) do
    trips = RideAlong.Adept.get_trips_by_route(v.route_id)
    state = update_trips(state, trips)
    {:noreply, state}
  end

  def update_trips(state, trips) do
    trips
    |> relevant_trips(DateTime.utc_now())
    |> Enum.reduce(state, &maybe_notify/2)
  end

  defp relevant_trips(all_trips, now) do
    # status is enroute/waiting (they're the next pickup) or diff is less than
    # 30m
    for trip <- all_trips,
        trip.pick_time != nil,
        trip.promise_time != nil,
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
    send? =
      cond do
        MapSet.member?(state.notified_trips, trip.trip_id) ->
          false

        not RideAlong.Singleton.singleton?() ->
          false

        state.client_ids != :all and trip.client_id not in state.client_ids ->
          false

        true ->
          true
      end

    if send? do
      send_notification(trip)
    end

    %{state | notified_trips: MapSet.put(state.notified_trips, trip.trip_id)}
  end

  defp send_notification(trip) do
    RideAlong.PubSub.publish(
      "notification:trip",
      {:trip_notification, trip}
    )
  end

  defp cleanup_old_notifications(state, all_trips) do
    # only keep trip IDs which are still in the `all_trips` list
    trip_ids = MapSet.new(all_trips, & &1.trip_id)
    %{state | notified_trips: MapSet.intersection(state.notified_trips, trip_ids)}
  end
end
