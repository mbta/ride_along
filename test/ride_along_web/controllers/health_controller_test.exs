defmodule RideAlongWeb.HEalthControllerTest do
  use RideAlongWeb.ConnCase

  test "GET /_health", %{conn: conn} do
    conn = get(conn, ~p"/_health")
    assert response(conn, 200)
  end
end
