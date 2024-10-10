defmodule RideAlongWeb.TripLive.Show do
  use RideAlongWeb, :live_view
  require Logger

  alias Faker.Address, as: FakeAddress
  alias RideAlong.Adept
  alias RideAlong.Adept.{Trip, Vehicle}
  alias RideAlong.EtaCalculator
  alias RideAlong.LinkShortener
  alias RideAlong.OpenRouteService
  alias RideAlong.OpenRouteService.Route
  import RideAlongWeb.TripComponents

  @impl true
  def mount(%{"token" => token} = params, session, socket) do
    Logger.metadata(
      token: token,
      uid: session["uid"]
    )

    trip = LinkShortener.get_trip(token)
    mount_trip(trip, params, socket)
  end

  def mount(%{"trip" => trip_id} = params, session, socket) do
    Logger.metadata(
      trip_id: trip_id,
      uid: session["uid"]
    )

    trip = Adept.get_trip(String.to_integer(trip_id))
    mount_trip(trip, params, socket)
  end

  defp mount_trip(%Trip{} = trip, params, socket) do
    Logger.metadata(
      trip_id: trip.trip_id,
      route_id: trip.route_id,
      client_id: trip.client_id
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
      |> assign(:feedback_url, Application.get_env(:ride_along, __MODULE__)[:feedback_url])
      |> assign(:now, DateTime.utc_now())
      |> assign(:page_title, gettext("Track your Trip"))
      |> assign(:trip, trip)
      |> assign(:route, nil)

    socket =
      case Adept.get_vehicle_by_route(trip.route_id) do
        %Vehicle{} = vehicle ->
          socket
          |> assign(:vehicle, vehicle)
          |> assign_status()
          |> assign_eta()
          |> request_route(false)
          |> assign_route()
          |> assign_popup()

        nil ->
          socket
          |> assign(:status, :closed)
      end

    socket =
      cond do
        socket.assigns.status == :closed ->
          redirect(socket, to: "/not-found")

        connected?(socket) ->
          Logger.info("mounted controller=#{__MODULE__} params=#{inspect(params)}")

          if socket.assigns.status != :picked_up do
            {:ok, ref} = :timer.send_interval(1_000, :countdown)
            RideAlong.PubSub.subscribe("vehicle:#{socket.assigns.vehicle.vehicle_id}")
            RideAlong.PubSub.subscribe("trips:updated")
            assign(socket, :countdown_ref, ref)
          else
            socket
          end

        true ->
          socket
      end

    {:ok, socket, layout: false}
  end

  defp mount_trip(nil, _params, socket) do
    {:ok, redirect(socket, to: "/not-found")}
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

    socket =
      case Adept.get_trip(old_trip.trip_id) do
        %Trip{} = new_trip ->
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

          socket
          |> assign(:trip, trip)
          |> assign_vehicle(old_trip)
          |> put_schedule_change_flash(old_trip)
          |> assign_status()
          |> assign_eta()
          |> request_route()
          |> assign_route()
          |> assign_popup()

        nil ->
          redirect(socket, to: "/not-found")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_async(:route, {:ok, {:ok, %Route{} = route}}, socket) do
    socket =
      socket
      |> assign(:route, route)
      |> assign_eta()
      |> assign_route()
      |> assign_popup()

    {:noreply, socket}
  end

  def handle_async(:route, {:ok, nil}, socket) do
    {:noreply,
     socket
     |> assign(:route, nil)
     |> assign_eta()
     |> assign_route()
     |> assign_popup()}
  end

  def handle_async(:route, {:ok, {:error, reason}}, socket) do
    Logger.warning("error calculating route reason=#{inspect(reason)}")

    {:noreply, socket}
  end

  def handle_async(:route, _, socket) do
    # ignore for now
    {:noreply, socket}
  end

  defp request_route(socket, async? \\ true) do
    source = socket.assigns.vehicle
    destination = socket.assigns.trip

    old_source =
      if socket.assigns.route do
        socket.assigns.route.source
      else
        %{}
      end

    async_fn =
      cond do
        socket.assigns.status not in [:enroute, :waiting] ->
          fn -> nil end

        Map.take(source, [:lat, :lon]) != Map.take(old_source, [:lat, :lon]) ->
          fn -> OpenRouteService.directions(source, destination) end

        true ->
          nil
      end

    cond do
      is_nil(async_fn) ->
        socket

      async? ->
        start_async(socket, :route, async_fn)

      true ->
        {:noreply, socket} = handle_async(:route, {:ok, async_fn.()}, socket)
        socket
    end
  end

  defp assign_vehicle(socket, old_trip) do
    if socket.assigns.trip.route_id == old_trip.route_id do
      socket
    else
      RideAlong.PubSub.unsubscribe("vehicle:#{socket.assigns.vehicle.vehicle_id}")

      case Adept.get_vehicle_by_route(socket.assigns.trip.route_id) do
        %Vehicle{} = vehicle ->
          RideAlong.PubSub.subscribe("vehicle:#{vehicle.vehicle_id}")
          assign(socket, :vehicle, vehicle)

        _ ->
          redirect(socket, to: "/not-found")
      end
    end
  end

  defp assign_eta(socket) do
    if eta = calculate_eta(socket.assigns) do
      socket
      |> assign(:eta, DateTime.to_iso8601(eta))
      |> assign(:eta_text, format_eta(eta, socket.assigns.now))
    else
      socket
      |> assign(:eta, nil)
      |> assign(:eta_text, nil)
    end
  end

  defp assign_status(socket) do
    new_status = status(socket.assigns)
    socket = assign(socket, :status, new_status)

    cond do
      new_status in [:picked_up, :closed] ->
        if socket.assigns[:countdown_ref] do
          :timer.cancel(socket.assigns.countdown_ref)
        end

        RideAlong.PubSub.unsubscribe("vehicle:#{socket.assigns.vehicle.vehicle_id}")
        RideAlong.PubSub.unsubscribe("trips:updated")

        assign(socket, :countdown_ref, nil)

      new_status == :arrived ->
        departure_text =
          if departure_time = Trip.departure_time(socket.assigns.trip) do
            gettext("until %{time}", %{time: format_time(departure_time)})
          else
            gettext("for up to five minutes")
          end

        assign(socket, :departure_text, departure_text)

      true ->
        socket
    end
  end

  def put_schedule_change_flash(socket, old_trip) do
    cond do
      socket.assigns.trip.route_id != old_trip.route_id ->
        put_flash(
          socket,
          :warning,
          gettext("Your estimated pick-up time and vehicle have changed.")
        )

      socket.assigns.trip.pick_order != old_trip.pick_order ->
        put_flash(socket, :warning, gettext("Your estimated pick-up time has changed."))

      true ->
        socket
    end
  end

  defp assign_route(%{assigns: %{status: :enroute, route: route}} = socket) when route != nil do
    socket
    |> assign(:bbox, Jason.encode!(route.bbox))
    |> assign(:polyline, route.polyline)
  end

  defp assign_route(
         %{
           assigns: %{
             status: status,
             vehicle: %{lat: %Decimal{}, lon: %Decimal{}},
             route: nil
           }
         } =
           socket
       )
       when status in [:enroute, :arrived] do
    vehicle_lat = Decimal.to_float(socket.assigns.vehicle.lat)
    vehicle_lon = Decimal.to_float(socket.assigns.vehicle.lon)

    bbox =
      Jason.encode!([
        [vehicle_lat, vehicle_lon],
        [Decimal.to_float(socket.assigns.trip.lat), Decimal.to_float(socket.assigns.trip.lon)]
      ])

    polyline =
      Polyline.encode([
        {vehicle_lon, vehicle_lat}
      ])

    socket
    |> assign(:bbox, bbox)
    |> assign(:polyline, polyline)
  end

  defp assign_route(socket) do
    socket
    |> assign(:bbox, nil)
    |> assign(:polyline, nil)
  end

  defp assign_popup(%{assigns: %{status: :waiting}} = socket) do
    assign(socket, :popup, gettext("Your RIDE is nearby and will pick you up shortly."))
  end

  defp assign_popup(socket) do
    assign(socket, :popup, nil)
  end

  def status(assigns) do
    %{
      trip: trip,
      vehicle: vehicle,
      now: now
    } = assigns

    Trip.status(trip, vehicle, now)
  end

  def calculate_eta(%{trip: trip, now: now} = assigns) do
    EtaCalculator.calculate(
      trip,
      Map.get(assigns, :vehicle),
      Map.get(assigns, :route),
      now
    )
  end

  def format_eta(dt, now) do
    minutes = round(max(DateTime.diff(dt, now, :second), 60) / 60)

    if minutes > 10 do
      {:time, format_time(dt)}
    else
      {:countdown, ngettext("1 minute", "%{count} minutes", minutes)}
    end
  end

  def format_time(dt) do
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
