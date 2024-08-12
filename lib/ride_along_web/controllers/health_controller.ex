defmodule RideAlongWeb.HealthController do
  use RideAlongWeb, :controller

  def index(conn, _params) do
    trip_count = RideAlong.Adept.all_trips_count()

    healthy? = trip_count != 0

    status =
      if healthy? do
        :ok
      else
        :service_unavailable
      end

    conn
    |> send_resp(status, "")
    |> halt()
  end
end
