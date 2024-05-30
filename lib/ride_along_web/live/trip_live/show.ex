defmodule RideAlongWeb.TripLive.Show do
  use RideAlongWeb, :live_view

  alias RideAlong.Adept
  alias RideAlong.Adept.{Trip, Vehicle}
  alias RideAlong.LinkShortener
  alias RideAlong.OpenRouteService
  alias RideAlong.OpenRouteService.Route

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    with trip = %Trip{} <- LinkShortener.get_trip(token),
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

  @impl true
  def handle_async(:route, {:ok, {:ok, %Route{} = route}}, socket) do
    {bbox1, bbox2} = route.bbox

    {:noreply,
     socket
     |> assign(:route, route)
     |> assign_eta()
     |> push_event("route", %{
       bbox: [[bbox1.lat, bbox1.lon], [bbox2.lat, bbox2.lon]],
       bearing: route.bearing,
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
    assign(socket, :status, status(socket.assigns))
  end

  def status(assigns) do
    %{
      trip: trip,
      vehicle: vehicle,
      now: now
    } = assigns

    hours_before_pick = DateTime.diff(trip.pick_time, now, :hour)

    cond do
      trip.pick_order - max(vehicle.last_pick, vehicle.last_drop) == 1 ->
        :enroute

      trip.dropoff_performed? ->
        :closed

      max(vehicle.last_pick, vehicle.last_drop) >= trip.drop_order ->
        :closed

      hours_before_pick > 0 ->
        :closed

      trip.pickup_performed? ->
        :picked_up

      max(vehicle.last_pick, vehicle.last_drop) >= trip.pick_order ->
        :picked_up

      true ->
        :enqueued
    end
  end

  def calculate_eta(%{route: %Route{}} = assigns) do
    now = assigns.now
    vehicle_timestamp = assigns.vehicle.timestamp
    duration_ms = trunc(assigns.route.duration * 1000)
    eta = DateTime.add(vehicle_timestamp, duration_ms, :millisecond)
    time_remaining = DateTime.diff(eta, now, :minute)

    cond do
      time_remaining >= 59 ->
        gettext("> 1 hour")

      time_remaining >= 0 ->
        ngettext("1 minute", "%{count} minutes", time_remaining + 1)

      true ->
        gettext("< 1 minute")
    end
  end

  def calculate_eta(%{trip: trip}) do
    Calendar.Strftime.strftime!(trip.pick_time, "%I:%M %p")
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
