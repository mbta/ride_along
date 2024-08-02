defmodule RideAlongWeb.Api.TokenController do
  @moduledoc """
  JSON:API for looking up tokens.
  """
  use RideAlongWeb, :controller

  alias RideAlong.Adept

  @view RideAlongWeb.TokenView

  plug :put_view, @view
  plug JSONAPI.QueryParser, view: @view, includes: ~w(vehicle)a

  def show(conn, %{"trip_id" => trip_id_bin}) do
    with {trip_id, ""} <- Integer.parse(trip_id_bin),
         trip = %Adept.Trip{} <- RideAlong.Adept.get_trip(trip_id),
         token when is_binary(token) <- RideAlong.LinkShortener.get_token(trip_id) do
      vehicle = Adept.get_vehicle_by_route(trip.route_id)
      now = DateTime.utc_now()

      status =
        trip
        |> Adept.Trip.status(vehicle, now)
        |> Atom.to_string()
        |> String.upcase()

      data = %{
        id: trip_id,
        url: url(~p"/t/#{token}"),
        status: status,
        promise_time: trip.promise_time,
        eta_time: trip.pick_time,
        vehicle: vehicle
      }

      render(conn, "show.json", %{data: data, meta: %{now: now}})
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> JSONAPI.ErrorView.send_error(:not_found, %{status: 404, code: "NOT_FOUND"})
        |> halt()
    end
  end
end
