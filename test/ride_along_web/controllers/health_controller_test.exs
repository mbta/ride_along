defmodule RideAlongWeb.HealthControllerTest do
  use RideAlongWeb.ConnCase

  test "GET /_health", %{conn: conn} do
    RideAlong.Adept.set_trips([])
    conn = get(conn, ~p"/_health")
    assert response(conn, 503)

    RideAlong.Adept.set_trips([RideAlong.AdeptFixtures.trip_fixture()])

    conn = get(conn, ~p"/_health")
    assert response(conn, 200)
  end
end
