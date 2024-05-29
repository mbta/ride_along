defmodule RideAlongWeb.HealthController do
  use RideAlongWeb, :controller

  def index(conn, _params) do
    trips = RideAlong.Adept.all_trips()

    healthy? = trips != []

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
