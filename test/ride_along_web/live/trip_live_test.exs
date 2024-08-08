defmodule RideAlongWeb.TripLiveTest do
  use RideAlongWeb.ConnCase

  import Phoenix.LiveViewTest

  alias RideAlong.AdeptFixtures, as: Fixtures
  alias RideAlong.OpenRouteService.Route
  alias RideAlongWeb.TripLive.Show

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

    test "unknown trip raises 404", %{conn: conn} do
      assert_raise RideAlongWeb.NotFoundException, fn -> live(conn, ~p"/t/missing") end
    end
  end

  describe "calculate_eta/1" do
    setup do
      {:ok, %{now: ~U[2024-05-31T15:43:40Z]}}
    end

    test "without a route, uses the pick time (formatted as H:MM am)", %{now: now} do
      pick_time = now

      assigns = %{
        trip: Fixtures.trip_fixture(%{pick_time: pick_time})
      }

      assert Show.format_eta(Show.calculate_eta(assigns)) == "3:43 PM"
    end

    test "with route, uses the duration plus the vehicle timestamp, rounding up", %{now: now} do
      assigns = %{
        trip: Fixtures.trip_fixture(%{promise_time: now}),
        vehicle: Fixtures.vehicle_fixture(%{timestamp: now}),
        route: %Route{duration: 60.5}
      }

      assert Show.format_eta(Show.calculate_eta(assigns)) == "3:45 PM"
    end

    test "does not use an ETA more than 5 minutes before the promise time", %{now: now} do
      # vehicle should not arrive more than 5 minutes early
      assigns = %{
        trip: Fixtures.trip_fixture(%{promise_time: ~U[2024-05-31T16:30:00Z]}),
        vehicle: Fixtures.vehicle_fixture(%{timestamp: now}),
        route: %Route{duration: 0}
      }

      assert Show.format_eta(Show.calculate_eta(assigns)) == "4:25 PM"
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
