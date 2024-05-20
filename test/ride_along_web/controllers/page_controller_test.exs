defmodule RideAlongWeb.PageControllerTest do
  use RideAlongWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "redirected automatically"
  end
end
