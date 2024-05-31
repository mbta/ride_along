defmodule RideAlongWeb.TripLive.Show do
  use RideAlongWeb, :live_view
  require Logger

  alias RideAlong.Adept
  alias RideAlong.Adept.{Trip, Vehicle}
  alias RideAlong.LinkShortener
  alias RideAlong.OpenRouteService
  alias RideAlong.OpenRouteService.Route

  @impl true
  def mount(%{"token" => token}, session, socket) do
    trip = LinkShortener.get_trip(token)
    mount_trip(trip, session, socket)
  end

  def mount(%{"trip" => trip_id}, session, socket) do
    trip = Adept.get_trip(String.to_integer(trip_id))
    mount_trip(trip, session, socket)
  end

  defp mount_trip(trip, _session, socket) do
    with trip = %Trip{} <- trip,
         vehicle = %Vehicle{} <- Adept.get_vehicle_by_route(trip.route_id) do
      socket =
        socket
        |> assign(:now, DateTime.utc_now())
        |> assign(:page_title, gettext("Track your Trip"))
        |> assign(:trip, trip)
        |> assign(:vehicle, vehicle)
        |> assign(:route, nil)
        |> assign_status()
        |> assign_eta()
        |> request_route()

      if socket.assigns.status == :closed do
        raise RideAlongWeb.NotFoundException
      end

      {:ok, socket}
    else
      _ -> raise RideAlongWeb.NotFoundException
    end
  end

  @impl true
  def handle_params(_, _, socket) do
    :timer.send_interval(1_000, :countdown)
    Phoenix.PubSub.subscribe(RideAlong.PubSub, "vehicle:#{socket.assigns.vehicle.vehicle_id}")
    Phoenix.PubSub.subscribe(RideAlong.PubSub, "trips:updated")

    {:noreply, socket}
  end

  @impl true
  def handle_info(:countdown, socket) do
    {:noreply,
     socket
     |> assign(:now, DateTime.utc_now())
     |> assign_status()
     |> assign_eta()}
  end

  def handle_info({:vehicle_updated, v}, socket) do
    {:noreply,
     socket
     |> assign(:vehicle, v)
     |> assign_status()
     |> assign_eta()
     |> request_route()}
  end

  def handle_info(:trips_updated, socket) do
    trip = Adept.get_trip(socket.assigns.trip.trip_id)

    {:noreply,
     socket
     |> assign(:trip, trip)
     |> assign_status()
     |> assign_eta()
     |> request_route()}
  end

  @impl true
  def handle_async(:route, {:ok, {:ok, %Route{} = route}}, socket) do
    trip = socket.assigns.trip

    eta =
      DateTime.add(socket.assigns.vehicle.timestamp, trunc(route.duration * 1000), :millisecond)

    {bbox1, bbox2} = route.bbox

    Logger.info(
      "#{__MODULE__} route calculated trip_id=#{trip.trip_id} route=#{trip.route_id} pick_time=#{DateTime.to_iso8601(trip.pick_time)} eta=#{DateTime.to_iso8601(eta)}"
    )

    {:noreply,
     socket
     |> assign(:route, route)
     |> assign_eta()
     |> push_event("route", %{
       bbox: [[bbox1.lat, bbox1.lon], [bbox2.lat, bbox2.lon]],
       bearing: socket.assigns.vehicle.heading,
       polyline: route.polyline
     })}
  end

  def handle_async(:route, {:ok, nil}, socket) do
    {:noreply,
     socket
     |> assign(:route, nil)
     |> assign_eta()
     |> push_event("clearRoute", %{})}
  end

  def handle_async(:route, _, socket) do
    # ignore for now
    {:noreply, socket}
  end

  defp request_route(socket) do
    source = socket.assigns.vehicle
    destination = socket.assigns.trip

    old_source =
      if socket.assigns.route do
        socket.assigns.route.source
      else
        %{}
      end

    cond do
      socket.assigns.status != :enroute ->
        start_async(socket, :route, fn -> nil end)

      Map.take(source, [:lat, :lon]) != Map.take(old_source, [:lat, :lon]) ->
        start_async(socket, :route, fn -> OpenRouteService.directions(source, destination) end)

      true ->
        socket
    end
  end

  defp assign_eta(socket) do
    assign(socket, :eta_text, calculate_eta(socket.assigns))
  end

  defp assign_status(socket) do
    old_status = Map.get(socket.assigns, :status)
    new_status = status(socket.assigns)

    if new_status != old_status do
      Logger.info(
        "#{__MODULE__} status trip_id=#{socket.assigns.trip.trip_id} route=#{socket.assigns.trip.route_id} pick_time=#{DateTime.to_iso8601(socket.assigns.trip.pick_time)} status=#{new_status}"
      )
    end

    if new_status in [:picked_up, :closed] do
      Phoenix.PubSub.unsubscribe(RideAlong.PubSub, "vehicle:#{socket.assigns.vehicle.vehicle_id}")
      Phoenix.PubSub.unsubscribe(RideAlong.PubSub, "trips:updated")
    end

    assign(socket, :status, new_status)
  end

  def status(assigns) do
    %{
      trip: trip,
      vehicle: vehicle,
      now: now
    } = assigns

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

  def calculate_eta(%{route: %Route{}} = assigns) do
    vehicle_timestamp = assigns.vehicle.timestamp
    duration_ms = trunc(assigns.route.duration * 1000)
    eta = DateTime.add(vehicle_timestamp, duration_ms, :millisecond)

    rounded_eta =
      if eta.second > 0 or elem(eta.microsecond, 0) > 0 do
        DateTime.add(eta, 1, :minute)
      else
        eta
      end

    earliest_arrival = DateTime.add(assigns.trip.promise_time, -5, :minute)

    if DateTime.compare(earliest_arrival, rounded_eta) == :gt do
      format_eta(earliest_arrival)
    else
      format_eta(rounded_eta)
    end
  end

  def calculate_eta(%{trip: trip}) do
    format_eta(trip.pick_time)
  end

  defp format_eta(dt) do
    dt
    |> Calendar.Strftime.strftime!("%l:%M %p")
    |> String.trim_leading()
  end

  def destination(trip) do
    Jason.encode_to_iodata!(
      %{
        lat: trip.lat,
        lon: trip.lon,
        alt: Trip.address(trip)
      },
      escape: :html_safe
    )
  end

  attr :title, :string, required: true
  attr :value, :any, required: true

  def labeled_field(assigns) do
    ~H"""
    <div><span class="font-bold"><%= @title %>:</span> <%= @value %></div>
    """
  end
end
