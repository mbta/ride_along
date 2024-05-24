defmodule RideAlongWeb.PageController do
  use RideAlongWeb, :controller

  def home(conn, _params) do
    config = Application.get_env(:ride_along, __MODULE__)

    redirect_to =
      if config[:redirect_to] do
        [external: config[:redirect_to]]
      else
        trip = List.first(RideAlong.Adept.all_trips())
        token = RideAlong.LinkShortener.get_token(trip.trip_id)
        [to: ~p[/t/#{token}]]
      end

    redirect(conn, redirect_to)
  end
end
