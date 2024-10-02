defmodule RideAlongWeb.TripLiveTest do
  use RideAlongWeb.ConnCase

  import Phoenix.LiveViewTest

  alias RideAlong.AdeptFixtures, as: Fixtures

  describe "Show" do
    setup [:ors, :adept]

    test "displays trip", %{conn: conn, token: token} do
      {:ok, _show_live, html} = live(conn, ~p"/t/#{token}")
      {:ok, document} = Floki.parse_document(html)
      map = Floki.get_by_id(document, "map")
      assert map != nil
      assert [_bbox] = Floki.attribute(map, "data-bbox")
      assert [_polyline] = Floki.attribute(map, "data-polyline")
    end

    test "ETA is in an aria-live region", %{conn: conn, token: token} do
      {:ok, _show_live, html} = live(conn, ~p"/t/#{token}")
      {:ok, document} = Floki.parse_document(html)
      elements = Floki.find(document, "[aria-live]")
      assert Floki.text(elements) =~ "Estimated time of pick-up"
    end

    @tag :capture_log
    test "unknown trip redirects to not-found", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/not-found"}}} = live(conn, ~p"/t/missing")
    end

    @tag :capture_log
    test "closed trip redirects to not-found", %{conn: conn, trip: trip, token: token} do
      RideAlong.Adept.set_trips([%{trip | dropoff_performed?: true}])
      assert {:error, {:redirect, %{to: "/not-found"}}} = live(conn, ~p"/t/#{token}")
    end

    @tag :capture_log
    test "does not show an estimate time if there's no promise or pick times", %{
      conn: conn,
      trip: trip,
      token: token
    } do
      trip = %{trip | promise_time: nil, pick_time: nil}
      RideAlong.Adept.set_trips([trip])
      {:ok, _show_live, html} = live(conn, ~p"/t/#{token}")
      {:ok, document} = Floki.parse_document(html)
      elements = Floki.find(document, "[aria-live]")
      text = Floki.text(elements)
      refute text =~ "Estimated"
      refute text =~ "promise"
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
    trip = Fixtures.trip_fixture()
    vehicle = Fixtures.vehicle_fixture()
    RideAlong.Adept.set_trips([trip])
    RideAlong.Adept.set_vehicles([vehicle])

    on_exit(fn ->
      RideAlong.Adept.set_trips([])
      RideAlong.Adept.set_vehicles([])
    end)

    token = RideAlong.LinkShortener.get_token(trip.trip_id)
    {:ok, trip: trip, vehicle: vehicle, token: token}
  end
end
