defmodule RideAlongWeb.TripLiveTest do
  use RideAlongWeb.ConnCase

  import Phoenix.LiveViewTest

  alias RideAlong.AdeptFixtures, as: Fixtures

  describe "Show" do
    setup [:ors, :adept]

    test "displays trip", %{conn: conn, token: token} do
      {:ok, _show_live, html} = live(conn, ~p"/t/#{token}")
      {:ok, document} = Floki.parse_document(html)
      assert Floki.get_by_id(document, "map") != nil
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
    test "closed trip redirects to not-found", %{conn: conn, vehicle: vehicle, token: token} do
      vehicle = %{vehicle | last_drop: 10}
      RideAlong.Adept.set_vehicles([vehicle])
      assert {:error, {:redirect, %{to: "/not-found"}}} = live(conn, ~p"/t/#{token}")
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
