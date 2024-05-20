defmodule RideAlongWeb.TripLive.Show do
  use RideAlongWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"token" => _id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, "Track your Trip")
     |> assign(:trip, nil)}
  end
end
