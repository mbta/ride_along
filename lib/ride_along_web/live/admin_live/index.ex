defmodule RideAlongWeb.AdminLive.Index do
  use RideAlongWeb, :live_view

  alias RideAlong.Adept

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      RideAlong.PubSub.subscribe("trips:updated")
      RideAlong.PubSub.subscribe("vehicles:all")
    end

    {:ok,
     socket
     |> assign(:page_title, "Admin - RideAlong")
     |> assign(:uid, session["uid"])
     |> assign(:now, DateTime.utc_now())
     |> assign(:demo?, false)
     |> stream_configure(:trips, dom_id: &"trips-#{elem(&1, 0).trip_id}")
     |> stream(:trips, open_trips())}
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
    {:noreply,
     socket
     |> assign(:now, DateTime.utc_now())
     |> stream(:trips, open_trips(), reset: true)}
  end

  def handle_info({:vehicle_updated, vehicle}, socket) do
    socket =
      vehicle.route_id
      |> Adept.get_trips_by_route()
      |> Enum.reduce(socket, fn trip, socket ->
        stream_insert(socket, :trips, {trip, vehicle})
      end)

    {:noreply,
     socket
     |> assign(:now, DateTime.utc_now())}
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

  def open_trips do
    now = DateTime.utc_now()
    earliest = DateTime.add(now, -5, :minute)

    trips =
      for trip <- Enum.sort(Adept.all_trips(), Adept.Trip),
          trip.promise_time != nil,
          DateTime.compare(earliest, trip.promise_time) == :lt,
          vehicle = Adept.get_vehicle_by_route(trip.route_id),
          status = Adept.Trip.status(trip, vehicle, now),
          status != :closed do
        {trip, vehicle}
      end

    Enum.sort_by(trips, &elem(&1, 0).promise_time, DateTime)
  end
end
