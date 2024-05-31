defmodule RideAlongWeb.TripLiveTest do
  use RideAlongWeb.ConnCase

  import Phoenix.LiveViewTest

  alias RideAlong.AdeptFixtures, as: Fixtures
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

    test "unknown trip raises 404", %{conn: conn} do
      assert_raise RideAlongWeb.NotFoundException, fn -> live(conn, ~p"/t/missing") end
    end
  end

  describe "status/1" do
    setup do
      now = DateTime.utc_now()
      trip = Fixtures.trip_fixture()
      vehicle = Fixtures.vehicle_fixture()
      {:ok, %{assigns: %{now: now, trip: trip, vehicle: vehicle}}}
    end

    test "is :enroute for the default fixture", %{assigns: assigns} do
      assert Show.status(assigns) == :enroute
    end

    test "is :closed if the trip was dropped off", %{assigns: assigns} do
      assigns = put_in(assigns.trip, Fixtures.trip_fixture(%{dropoff_performed?: true}))

      assert Show.status(assigns) == :closed
    end

    test "is :closed if the vehicle has performed something after the dropoff", %{
      assigns: assigns
    } do
      trip = assigns.trip

      assigns =
        put_in(assigns.vehicle, Fixtures.vehicle_fixture(%{last_pick: trip.drop_order + 2}))

      assert Show.status(assigns) == :closed

      assigns =
        put_in(assigns.vehicle, Fixtures.vehicle_fixture(%{last_drop: trip.drop_order + 1}))

      assert Show.status(assigns) == :closed
    end

    test "is :closed if the trip is more than an hour in the future", %{assigns: assigns} do
      assigns = put_in(assigns.now, DateTime.add(assigns.now, -61, :minute))

      assert Show.status(assigns) == :closed
    end

    test "is :picked_up if the trip was picked up", %{assigns: assigns} do
      assigns = put_in(assigns.trip, Fixtures.trip_fixture(%{pickup_performed?: true}))

      assert Show.status(assigns) == :picked_up
    end

    test "is :picked_up if the vehicle has performed something after the pickup", %{
      assigns: assigns
    } do
      trip = assigns.trip

      assigns =
        put_in(assigns.vehicle, Fixtures.vehicle_fixture(%{last_pick: trip.pick_order}))

      assert Show.status(assigns) == :picked_up

      assigns =
        put_in(assigns.vehicle, Fixtures.vehicle_fixture(%{last_drop: trip.pick_order + 1}))

      assert Show.status(assigns) == :picked_up
    end

    test "is :arrived if the current trip is the last arrived trip", %{assigns: assigns} do
      trip = assigns.trip

      assigns =
        put_in(assigns.vehicle, Fixtures.vehicle_fixture(%{last_arrived_trip: trip.trip_id}))

      assert Show.status(assigns) == :arrived
    end

    test "is :enqueued if there is more than one pickup/dropoff before our pickup", %{
      assigns: assigns
    } do
      trip = assigns.trip

      assigns =
        put_in(
          assigns.vehicle,
          Fixtures.vehicle_fixture(%{
            last_pick: trip.pick_order - 3,
            last_drop: trip.pick_order - 2
          })
        )

      assert Show.status(assigns) == :enqueued
    end

    test "is :enroute if there is exactly one pickup/dropoff before our pickup", %{
      assigns: assigns
    } do
      trip = assigns.trip

      assigns =
        put_in(
          assigns.vehicle,
          Fixtures.vehicle_fixture(%{
            last_pick: trip.pick_order - 1,
            last_drop: trip.pick_order - 2
          })
        )

      assert Show.status(assigns) == :enroute
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

    :ok
  end
end
