defmodule RideAlongWeb.TripLive.Show do
  use RideAlongWeb, :live_view
  require Logger

  alias Faker.Address, as: FakeAddress
  alias RideAlong.Adept
  alias RideAlong.Adept.{Trip, Vehicle}
  alias RideAlong.LinkShortener
  alias RideAlong.OpenRouteService
  alias RideAlong.OpenRouteService.Route
  import RideAlongWeb.TripComponents

  @impl true
  def mount(%{"token" => token} = params, _session, socket) do
    trip = LinkShortener.get_trip(token)
    mount_trip(trip, params, socket)
  end

  def mount(%{"trip" => trip_id} = params, _session, socket) do
    trip = Adept.get_trip(String.to_integer(trip_id))
    mount_trip(trip, params, socket)
  end

  defp mount_trip(trip, params, socket) do
    with trip = %Trip{} <- trip,
         vehicle = %Vehicle{} <- Adept.get_vehicle_by_route(trip.route_id) do
      Logger.metadata(
        token: params["token"],
        trip_id: trip.trip_id,
        route_id: trip.route_id
      )

      trip =
        if is_nil(params["demo"]) do
          trip
        else
          %{
            trip
            | house_number: FakeAddress.building_number(),
              address1: FakeAddress.street_name(),
              address2: FakeAddress.secondary_address(),
              city: FakeAddress.city(),
              state: FakeAddress.state_abbr(),
              zip: FakeAddress.zip()
          }
        end

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

      if connected?(socket) do
        Logger.info("mounted controller=#{__MODULE__} params=#{inspect(params)}")

        :timer.send_interval(1_000, :countdown)
        Phoenix.PubSub.subscribe(RideAlong.PubSub, "vehicle:#{socket.assigns.vehicle.vehicle_id}")
        Phoenix.PubSub.subscribe(RideAlong.PubSub, "trips:updated")
      end

      {:ok, socket, layout: false}
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
    old_trip = socket.assigns.trip
    new_trip = Adept.get_trip(old_trip.trip_id)

    # keep the old address if we're in demo mode
    trip = %{
      new_trip
      | house_number: old_trip.house_number,
        address1: old_trip.address1,
        address2: old_trip.address2,
        city: old_trip.city,
        state: old_trip.state,
        zip: old_trip.zip
    }

    {:noreply,
     socket
     |> assign(:trip, trip)
     |> assign_vehicle(old_trip)
     |> put_schedule_change_flash(old_trip)
     |> assign_status()
     |> assign_eta()
     |> push_route()
     |> request_route()}
  end

  @impl true
  def handle_async(:route, {:ok, {:ok, %Route{} = route}}, socket) do
    eta =
      DateTime.add(socket.assigns.vehicle.timestamp, trunc(route.duration * 1000), :millisecond)

    Logger.info("#{__MODULE__} route calculated eta=#{DateTime.to_iso8601(eta)}")

    {:noreply,
     socket
     |> assign(:route, route)
     |> assign_eta()
     |> push_route()}
  end

  def handle_async(:route, {:ok, nil}, socket) do
    {:noreply,
     socket
     |> assign(:route, nil)
     |> assign_eta()
     |> push_route()}
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
      socket.assigns.status not in [:enroute, :waiting] ->
        start_async(socket, :route, fn -> nil end)

      Map.take(source, [:lat, :lon]) != Map.take(old_source, [:lat, :lon]) ->
        start_async(socket, :route, fn -> OpenRouteService.directions(source, destination) end)

      true ->
        socket
    end
  end

  defp assign_vehicle(socket, old_trip) do
    if socket.assigns.trip.route_id == old_trip.route_id do
      socket
    else
      Phoenix.PubSub.unsubscribe(RideAlong.PubSub, "vehicle:#{socket.assigns.vehicle.vehicle_id}")

      case Adept.get_vehicle_by_route(socket.assigns.trip.route_id) do
        %Vehicle{} = vehicle ->
          Phoenix.PubSub.subscribe(RideAlong.PubSub, "vehicle:#{vehicle.vehicle_id}")
          assign(socket, :vehicle, vehicle)

        _ ->
          raise RideAlongWeb.NotFoundException
      end
    end
  end

  defp assign_eta(socket) do
    eta = calculate_eta(socket.assigns)

    socket
    |> assign(:eta, DateTime.to_iso8601(eta))
    |> assign(:eta_text, format_eta(eta))
  end

  defp assign_status(socket) do
    old_status = Map.get(socket.assigns, :status)
    new_status = status(socket.assigns)

    if new_status != old_status do
      Logger.info(
        "#{__MODULE__} status pick_time=#{DateTime.to_iso8601(socket.assigns.trip.pick_time)} status=#{new_status}"
      )
    end

    if new_status in [:picked_up, :closed] do
      Phoenix.PubSub.unsubscribe(RideAlong.PubSub, "vehicle:#{socket.assigns.vehicle.vehicle_id}")
      Phoenix.PubSub.unsubscribe(RideAlong.PubSub, "trips:updated")
    end

    assign(socket, :status, new_status)
  end

  def put_schedule_change_flash(socket, old_trip) do
    cond do
      socket.assigns.trip.route_id != old_trip.route_id ->
        put_flash(socket, :warning, gettext("Your ETA and vehicle have changed."))

      socket.assigns.trip.pick_order != old_trip.pick_order ->
        put_flash(socket, :warning, gettext("Your ETA has changed."))

      true ->
        socket
    end
  end

  defp push_route(%{assigns: %{status: :enroute, route: route}} = socket) when route != nil do
    %{vehicle: vehicle} = socket.assigns

    {bbox1, bbox2} = route.bbox

    push_event(socket, "route", %{
      bbox: [[bbox1.lat, bbox1.lon], [bbox2.lat, bbox2.lon]],
      bearing: vehicle.heading,
      polyline: route.polyline
    })
  end

  defp push_route(socket) do
    popup =
      case socket.assigns.status do
        :waiting ->
          gettext("Your RIDE is nearby and will pick you up shortly.")

        :arrived ->
          gettext("Your RIDE is here!")

        _ ->
          nil
      end

    push_event(socket, "clearRoute", %{
      popup: popup
    })
  end

  def status(assigns) do
    %{
      trip: trip,
      vehicle: vehicle,
      now: now
    } = assigns

    Trip.status(trip, vehicle, now)
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
      earliest_arrival
    else
      rounded_eta
    end
  end

  def calculate_eta(%{trip: trip}) do
    trip.pick_time
  end

  def format_eta(dt) do
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
end
