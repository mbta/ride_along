defmodule RideAlongWeb.TripLiveTest do
  use RideAlongWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Show" do
    setup :ors

    test "displays trip", %{conn: conn} do
      trip = List.first(RideAlong.Adept.all_trips())
      token = RideAlong.LinkShortener.get_token(trip.trip_id)
      {:ok, _show_live, html} = live(conn, ~p"/t/#{token}")
      {:ok, document} = Floki.parse_document(html)
      assert Floki.get_by_id(document, "map") != nil
    end

    test "unknown trip raises 404", %{conn: conn} do
      assert_raise RideAlongWeb.NotFoundException, fn -> live(conn, ~p"/t/missing") end
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
