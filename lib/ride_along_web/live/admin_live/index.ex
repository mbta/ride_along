defmodule RideAlongWeb.AdminLive.Index do
  use RideAlongWeb, :live_view

  alias RideAlong.Adept

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(RideAlong.PubSub, "trips:updated")
    end

    {:ok,
     socket
     |> assign(:now, DateTime.utc_now())
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
  def handle_event("update", params, socket) do
    {:noreply,
     push_patch(
       socket,
       to: ~p"/admin?#{params}"
     )}
  end

  @impl true
  def handle_info(:trips_updated, socket) do
    {:noreply,
     socket
     |> assign(:now, DateTime.utc_now())
     |> stream(:trips, open_trips(), reset: true)}
  end

  defp assign_iframe(socket) do
    iframe_url =
      with trip_id_bin when is_binary(trip_id_bin) <- socket.assigns.form.params["trip_id"],
           {trip_id, ""} <- Integer.parse(trip_id_bin),
           token when is_binary(token) <- RideAlong.LinkShortener.get_token(trip_id) do
        url(~p"/t/#{token}")
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
