defmodule RideAlongWeb.TripLive.Show do
  use RideAlongWeb, :live_view

  @destination %{
    alt: "Boston, MA",
    lat: 42.3516728,
    lon: -71.0718109
  }
  @vehicle %{
    lat: 42.3516768,
    lon: -71.0695149
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
    {:noreply,
     socket
     |> assign(:page_title, "Track your Trip")
     |> assign(:vehicle, @vehicle)
     |> assign(:destination, @destination)
     |> assign(:trip, nil)}
  end

  @impl true
  def handle_event(_event, _data, socket) do
    {:noreply, socket}
  end
end
