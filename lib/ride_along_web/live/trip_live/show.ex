defmodule RideAlongWeb.TripLive.Show do
  use RideAlongWeb, :live_view

  alias RideAlong.OpenRouteService
  alias RideAlong.OpenRouteService.Route

  @destination %{
    alt: "Boston, MA",
    lat: 42.3516728,
    lon: -71.0718109
  }
  @vehicle %{
    lat: 42.3516768,
    lon: -71.0695149,
    bearing: 65
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> push_event("destination", @destination)
     |> push_event("vehicle", @vehicle)}
  end

  @impl true
  def handle_params(%{"token" => _id}, _, socket) do
    socket =
      socket
      |> assign(:page_title, "Track your Trip")
      |> assign(:vehicle, @vehicle)
      |> assign(:destination, @destination)
      |> assign(:trip, nil)

    request_route!(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_event("vehicle-moved", data, socket) do
    vehicle = socket.assigns.vehicle
    new_vehicle = %{vehicle | lat: data["lat"], lon: data["lng"]}
    socket = assign(socket, :vehicle, new_vehicle)

    if vehicle != new_vehicle do
      request_route!(socket)
    end

    {:noreply, socket}
  end

  def handle_event("destination-moved", data, socket) do
    destination = socket.assigns.destination
    new_destination = %{destination | lat: data["lat"], lon: data["lng"]}
    socket = assign(socket, :destination, new_destination)

    if destination != new_destination do
      request_route!(socket)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({_ref, {:ok, %Route{} = route}}, socket) do
    {bbox1, bbox2} = route.bbox
    vehicle = socket.assigns.vehicle
    new_vehicle = %{vehicle | bearing: route.bearing}

    {:noreply,
     socket
     |> assign(:vehicle, new_vehicle)
     |> push_event("vehicle", new_vehicle)
     |> push_event("route", %{
       bbox: [[bbox1.lat, bbox1.lon], [bbox2.lat, bbox2.lon]],
       polyline: route.polyline
     })}
  end

  def handle_info({_ref, {:error, _}}, socket) do
    # ignore for now
    {:noreply, socket}
  end

  def handle_info({:DOWN, _, _, _, _}, socket) do
    {:noreply, socket}
  end

  defp request_route!(socket) do
    source = socket.assigns.vehicle
    destination = socket.assigns.destination
    Task.async(OpenRouteService, :directions, [source, destination])
  end
end
