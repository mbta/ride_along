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
    trip = LinkShortener.get_trip(token)
    mount_trip(trip, params, session, socket)
  end

  def mount(%{"trip" => trip_id} = params, session, socket) do
    trip = Adept.get_trip(String.to_integer(trip_id))
    mount_trip(trip, params, session, socket)
  end

  defp mount_trip(trip, params, session, socket) do
    Logger.metadata(
      token: params["token"],
      uid: session["uid"]
    )

    with trip = %Trip{} <- trip,
         Logger.metadata(
           trip_id: trip.trip_id,
           route_id: trip.route_id,
           client_id: trip.client_id
         ),
         vehicle = %Vehicle{} <- Adept.get_vehicle_by_route(trip.route_id) do
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
        |> assign(:vehicle, vehicle)
        |> assign(:route, nil)
        |> assign_status()
        |> assign_eta()
        |> request_route(false)
        |> push_route()

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
    else
      _ ->
        {:ok, redirect(socket, to: "/not-found")}
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
     |> request_route()
     |> push_route()}
  end

  @impl true
  def handle_async(:route, {:ok, {:ok, %Route{} = route}}, socket) do
    socket =
      socket
      |> assign(:route, route)
      |> assign_eta()
      |> push_route()

    {:noreply, socket}
  end

  def handle_async(:route, {:ok, nil}, socket) do
    {:noreply,
     socket
     |> assign(:route, nil)
     |> assign_eta()
     |> push_route()}
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
      |> assign(:eta_text, format_eta(eta))
    else
      socket
      |> assign(:eta, nil)
      |> assign(:eta_text, nil)
    end
  end

  defp assign_status(socket) do
    new_status = status(socket.assigns)

    socket =
      if new_status in [:picked_up, :closed] do
        if socket.assigns[:countdown_ref] do
          :timer.cancel(socket.assigns.countdown_ref)
        end

        RideAlong.PubSub.unsubscribe("vehicle:#{socket.assigns.vehicle.vehicle_id}")
        RideAlong.PubSub.unsubscribe("trips:updated")

        assign(socket, :countdown_ref, nil)
      else
        socket
      end

    assign(socket, :status, new_status)
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

  defp push_route(%{assigns: %{status: :enroute, route: route}} = socket) when route != nil do
    socket
    |> assign(:bbox, Jason.encode!(route.bbox))
    |> assign(:polyline, route.polyline)
    |> assign(:popup, nil)
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

    socket
    |> assign(:bbox, nil)
    |> assign(:polyline, nil)
    |> assign(:popup, popup)
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
