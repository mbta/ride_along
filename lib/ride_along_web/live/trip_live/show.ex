defmodule RideAlongWeb.TripLive.Show do
  use RideAlongWeb, :live_view

  alias RideAlong.Adept
  alias RideAlong.Adept.{Route, Trip, Vehicle}
  alias RideAlong.LinkShortener
  alias RideAlong.OpenRouteService
  alias RideAlong.OpenRouteService.Route, as: Path

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    with trip = %Trip{} <- LinkShortener.get_trip(token),
         route = %Route{} <- Adept.get_route(trip.route_id),
         vehicle = %Vehicle{} <- Adept.get_vehicle(route.vehicle_id) do
      :timer.send_interval(1_000, :countdown)
      Phoenix.PubSub.subscribe(RideAlong.PubSub, "vehicle:#{vehicle.vehicle_id}")

      socket =
        socket
        |> assign(:now, DateTime.utc_now())
        |> assign(:page_title, gettext("Track your Trip"))
        |> assign(:trip, trip)
        |> assign(:route, route)
        |> assign(:vehicle, vehicle)
        |> assign(:path, nil)
        |> assign_eta()
        |> request_path()

      {:ok, socket}
    else
      _ -> raise RideAlongWeb.NotFoundException
    end
  end

  @impl true
  def handle_params(_, _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(:countdown, socket) do
    {:noreply,
     socket
     |> assign(:now, DateTime.utc_now())
     |> assign_eta()}
  end

  def handle_info({:vehicle_updated, v}, socket) do
    {:noreply,
     socket
     |> assign(:vehicle, v)
     |> request_path()}
  end

  @impl true
  def handle_async(:path, {:ok, {:ok, %Path{} = path}}, socket) do
    {bbox1, bbox2} = path.bbox

    {:noreply,
     socket
     |> assign(:path, path)
     |> assign_eta()
     |> push_event("path", %{
       bbox: [[bbox1.lat, bbox1.lon], [bbox2.lat, bbox2.lon]],
       bearing: path.bearing,
       polyline: path.polyline
     })}
  end

  def handle_async(:path, _, socket) do
    # ignore for now
    {:noreply, socket}
  end

  defp request_path(socket) do
    source = socket.assigns.vehicle
    destination = socket.assigns.trip

    old_source =
      if socket.assigns.path do
        socket.assigns.path.source
      else
        %{}
      end

    if Map.take(source, [:lat, :lon]) == Map.take(old_source, [:lat, :lon]) do
      socket
    else
      start_async(socket, :path, fn -> OpenRouteService.directions(source, destination) end)
    end
  end

  defp assign_eta(socket) do
    assign(socket, :eta_text, calculate_eta(socket.assigns))
  end

  def calculate_eta(%{path: %Path{}} = assigns) do
    now = assigns.now
    vehicle_timestamp = assigns.vehicle.timestamp
    duration_ms = trunc(assigns.path.duration * 1000)
    eta = DateTime.add(vehicle_timestamp, duration_ms, :millisecond)
    time_remaining = DateTime.diff(eta, now, :second)

    cond do
      time_remaining >= 60 * 60 ->
        gettext("> 1 hour")

      time_remaining >= 60 ->
        minutes = div(time_remaining, 60)
        ngettext("%{count} minute", "%{count} minutes", minutes)

      true ->
        gettext("< 1 minute")
    end
  end

  def calculate_eta(_assigns) do
    "Unknown"
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
