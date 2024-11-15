defmodule RideAlongWeb.AdminLive.Index do
  @moduledoc false
  use RideAlongWeb, :live_view

  alias RideAlong.Adept

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      RideAlong.PubSub.subscribe("trips:updated")
      RideAlong.PubSub.subscribe("vehicle:all")
    end

    trips = open_trips()

    {:ok,
     socket
     |> assign(:page_title, "Admin - Ride Along")
     |> assign(:uid, session["uid"])
     |> assign(:now, DateTime.utc_now())
     |> assign(:demo?, false)
     |> assign(:trips, trips)
     |> stream_configure(:trips, dom_id: &"trips-#{elem(&1, 0).trip_id}")
     |> stream(:trips, trips)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(:form, to_form(params))
     |> assign_iframe()}
  end

  @impl true
  def handle_event("update", %{"close" => _}, socket) do
    {:noreply,
     push_patch(
       socket,
       to: ~p"/admin"
     )}
  end

  def handle_event("update", params, socket) do
    {:noreply,
     push_patch(
       socket,
       to: ~p"/admin?#{params}"
     )}
  end

  def handle_event("demo", params, socket) do
    {:noreply,
     socket
     |> assign(:demo?, params["value"] == "true")
     |> assign_iframe()}
  end

  @impl true
  def handle_info(:trips_updated, socket) do
    trips = open_trips()

    {:noreply,
     socket
     |> assign(:now, DateTime.utc_now())
     |> assign(:trips, trips)
     |> stream(:trips, trips, reset: true)}
  end

  def handle_info({:vehicle_updated, vehicle}, socket) do
    socket = assign(socket, :now, DateTime.utc_now())

    socket =
      vehicle.route_id
      |> Adept.get_trips_by_route()
      |> Enum.reduce(socket, &reduce_vehicle_update(vehicle, &1, &2))

    {:noreply, socket}
  end

  defp assign_iframe(socket) do
    iframe_url =
      with trip_id_bin when is_binary(trip_id_bin) <- socket.assigns.form.params["trip_id"],
           {trip_id, ""} <- Integer.parse(trip_id_bin),
           token when is_binary(token) <- RideAlong.LinkShortener.get_token(trip_id) do
        if socket.assigns.demo? do
          url(~p"/t/#{token}?demo")
        else
          url(~p"/t/#{token}")
        end
      else
        _ -> nil
      end

    assign(socket, :iframe_url, iframe_url)
  end

  defp reduce_vehicle_update(vehicle, trip, socket) do
    case RideAlong.Adept.Trip.status(trip, vehicle, socket.assigns.now) do
      :closed ->
        stream_delete(socket, :trips, {trip, vehicle})

      _other ->
        if Enum.any?(socket.assigns.trips, &(elem(&1, 0).trip_id == trip.trip_id)) do
          stream_insert(socket, :trips, {trip, vehicle})
        else
          socket
        end
    end
  end

  def open_trips do
    now = DateTime.utc_now()
    earliest = DateTime.add(now, -5, :minute)

    trips =
      for trip <- Enum.sort(Adept.all_trips(), Adept.Trip),
          trip.promise_time != nil,
          vehicle = Adept.get_vehicle_by_route(trip.route_id),
          status = Adept.Trip.status(trip, vehicle, now),
          status != :closed,
          status != :picked_up or DateTime.before?(earliest, trip.promise_time) do
        {trip, vehicle}
      end

    Enum.sort_by(trips, &elem(&1, 0).promise_time, DateTime)
  end
end
