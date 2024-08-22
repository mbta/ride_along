defmodule RideAlongWeb.TripLiveTest do
  use RideAlongWeb.ConnCase

  import Phoenix.LiveViewTest

  alias RideAlong.AdeptFixtures, as: Fixtures

  describe "Show" do
    setup [:ors, :adept]

    test "displays trip", %{conn: conn} do
      trip = List.first(RideAlong.Adept.all_trips())
      token = RideAlong.LinkShortener.get_token(trip.trip_id)
      {:ok, _show_live, html} = live(conn, ~p"/t/#{token}")
      {:ok, document} = Floki.parse_document(html)
      assert Floki.get_by_id(document, "map") != nil
    end

    test "ETA is in an aria-live region", %{conn: conn} do
      trip = List.first(RideAlong.Adept.all_trips())
      token = RideAlong.LinkShortener.get_token(trip.trip_id)
      {:ok, _show_live, html} = live(conn, ~p"/t/#{token}")
      {:ok, document} = Floki.parse_document(html)
      elements = Floki.find(document, "[aria-live]")
      assert Floki.text(elements) =~ "ETA"
    end

    @tag :capture_log
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

  def adept(_) do
    RideAlong.Adept.set_trips([Fixtures.trip_fixture()])
    RideAlong.Adept.set_vehicles([Fixtures.vehicle_fixture()])

    on_exit(fn ->
      RideAlong.Adept.set_trips([])
      RideAlong.Adept.set_vehicles([])
    end)

    :ok
  end
end
