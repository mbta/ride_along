defmodule RideAlongWeb.TripLiveTest do
  use RideAlongWeb.ConnCase

  import Phoenix.LiveViewTest

  alias RideAlong.AdeptFixtures, as: Fixtures
  alias RideAlong.OpenRouteServiceFixtures, as: ORSFixtures

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
      assert Floki.text(elements) =~ "Status"
    end

    test "shows a vehicle and the 5 minute departure when the trip has arrived", %{
      conn: conn,
      trip: trip,
      vehicle: vehicle,
      token: token
    } do
      vehicle = %{vehicle | last_arrived_trips: [trip.trip_id], timestamp: DateTime.utc_now()}
      RideAlong.Adept.set_vehicles([vehicle])

      {:ok, _show_live, html} = live(conn, ~p"/t/#{token}")
      {:ok, document} = Floki.parse_document(html)

      map = Floki.get_by_id(document, "map")
      assert [_bbox] = Floki.attribute(map, "data-bbox")
      assert [_polyline] = Floki.attribute(map, "data-polyline")
      assert [_heading] = Floki.attribute(map, "data-vehicle-heading")

      status = Floki.get_by_id(document, "status")

      assert Floki.text(status) =~
               "The driver will go to your door and wait for up to five minutes."
    end

    test "shows the time 5 minutes after the promise time if the driver arrives early", %{
      conn: conn,
      trip: trip,
      token: token
    } do
      promise_time = DateTime.from_naive!(~N[2024-10-08T12:28:00], "America/New_York")

      trip = %{
        trip
        | promise_time: promise_time,
          pickup_arrival_time: DateTime.add(promise_time, -10, :minute)
      }

      RideAlong.Adept.set_trips([trip])
      {:ok, _show_live, html} = live(conn, ~p"/t/#{token}")
      {:ok, document} = Floki.parse_document(html)

      status = Floki.get_by_id(document, "status")
      assert Floki.text(status) =~ "The driver will go to your door and wait until 12:33 PM."
    end

    test "shows an Update X minutes ago message if the location is stale", %{
      conn: conn,
      vehicle: vehicle,
      token: token
    } do
      vehicle =
        %{vehicle | timestamp: DateTime.add(vehicle.timestamp, -5, :minute)}

      # need to reset the vehicles, because otherwise we can't go back in time
      # with the vehicle timestamp
      RideAlong.Adept.set_vehicles([])
      RideAlong.Adept.set_vehicles([vehicle])

      {:ok, _show_live, html} = live(conn, ~p"/t/#{token}")
      {:ok, document} = Floki.parse_document(html)

      assert Floki.text(document) =~ "Updated 5 minutes ago"
    end

    test "shows a flash message if the vehicle changes but the route is the same", %{
      conn: conn,
      vehicle: vehicle,
      token: token
    } do
      vehicle =
        %{vehicle | timestamp: DateTime.add(vehicle.timestamp, 1, :second), vehicle_id: "new"}

      {:ok, show_live, _html} = live(conn, ~p"/t/#{token}")

      RideAlong.Adept.set_vehicles([vehicle])

      # receive do
      #   x -> IO.inspect(x)
      # end

      html = render_async(show_live)

      {:ok, document} = Floki.parse_document(html)
      flash = Floki.find(document, "[role=alert]:not([hidden])")
      assert Floki.text(flash) =~ "vehicle have changed"
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
    ORSFixtures.stub(ORSFixtures.fixture())
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
