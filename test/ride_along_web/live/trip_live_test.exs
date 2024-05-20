defmodule RideAlongWeb.TripLiveTest do
  use RideAlongWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Show" do
    test "displays trip", %{conn: conn} do
      {:ok, _show_live, html} = live(conn, ~p"/track/1234")
      {:ok, document} = Floki.parse_document(html)
      assert Floki.get_by_id(document, "map") != nil
    end
  end
end
