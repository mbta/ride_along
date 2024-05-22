defmodule RideAlongWeb.TripLiveTest do
  use RideAlongWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Show" do
    setup :ors

    test "displays trip", %{conn: conn} do
      {:ok, _show_live, html} = live(conn, ~p"/track/1234")
      {:ok, document} = Floki.parse_document(html)
      assert Floki.get_by_id(document, "map") != nil
    end
  end

  def ors(_) do
    Req.Test.stub(RideAlong.OpenRouteService, fn conn ->
      conn
      |> put_status(500)
      |> Req.Test.json(%{})
    end)

    :ok

  end
end
