defmodule RideAlongWeb.AdminLive.Index do
  use RideAlongWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
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

  defp assign_iframe(socket) do
    iframe_url =
      with trip_id_bin when is_binary(trip_id_bin) <- socket.assigns.form.params["trip_id"],
           {trip_id, ""} <- Integer.parse(trip_id_bin),
           token when is_binary(token) <- RideAlong.LinkShortener.get_token(trip_id) do
        ~p"/t/#{token}"
      else
        _ -> nil
      end

    assign(socket, :iframe_url, iframe_url)
  end
end
