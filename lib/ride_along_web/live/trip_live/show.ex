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
    :timer.send_interval(1_000, self(), :countdown)

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
      |> assign(:now, DateTime.utc_now())
      |> assign(:route, nil)
      |> assign_eta()
      |> request_route()

    {:noreply, socket}
  end

  @impl true
  def handle_event("vehicle-moved", data, socket) do
    vehicle = socket.assigns.vehicle
    new_vehicle = %{vehicle | lat: data["lat"], lon: data["lng"]}

    {:noreply,
     socket
     |> assign(:vehicle, new_vehicle)
     |> request_route()}
  end

  def handle_event("destination-moved", data, socket) do
    destination = socket.assigns.destination
    new_destination = %{destination | lat: data["lat"], lon: data["lng"]}

    {:noreply,
     socket
     |> assign(:destination, new_destination)
     |> request_route()}
  end

  @impl true
  def handle_info(:countdown, socket) do
    {:noreply,
     socket
     |> assign(:now, DateTime.utc_now())
     |> assign_eta()}
  end

  @impl true
  def handle_async(:route, {:ok, {:ok, %Route{} = route}}, socket) do
    {bbox1, bbox2} = route.bbox
    vehicle = socket.assigns.vehicle
    new_vehicle = %{vehicle | bearing: route.bearing}

    {:noreply,
     socket
     |> assign(:vehicle, new_vehicle)
     |> assign(:route, route)
     |> assign_eta()
     |> push_event("vehicle", new_vehicle)
     |> push_event("route", %{
       bbox: [[bbox1.lat, bbox1.lon], [bbox2.lat, bbox2.lon]],
       polyline: route.polyline
     })}
  end

  def handle_async(:route, _, socket) do
    # ignore for now
    {:noreply, socket}
  end

  defp request_route(socket) do
    source = socket.assigns.vehicle
    destination = socket.assigns.destination

    old_route =
      if socket.assigns.route do
        socket.assigns.route
      else
        %{source: %{}, destination: %{}}
      end

    if Map.take(source, [:lat, :lon]) == Map.take(old_route.source, [:lat, :lon]) and
         Map.take(destination, [:lat, :lon]) == Map.take(old_route.destination, [:lat, :lon]) do
      socket
    else
      start_async(socket, :route, fn -> OpenRouteService.directions(source, destination) end)
    end
  end

  defp assign_eta(socket) do
    assign(socket, :eta_text, calculate_eta(socket.assigns))
  end

  def calculate_eta(%{route: %Route{}} = assigns) do
    now = assigns.now
    query_timestamp = assigns.route.timestamp
    duration_ms = trunc(assigns.route.duration * 1000)
    eta = DateTime.add(query_timestamp, duration_ms, :millisecond)
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
end
