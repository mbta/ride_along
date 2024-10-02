defmodule RideAlongWeb.AdminLiveTest do
  @moduledoc false
  use RideAlongWeb.ConnCase

  import Phoenix.LiveViewTest

  alias RideAlong.Adept
  alias RideAlong.AdeptFixtures, as: Fixtures

  describe "Index" do
    setup [:login, :adept]

    test "default is a message without an iframe", %{conn: conn} do
      {:ok, _, html} = live(conn, ~p"/admin")
      {:ok, document} = Floki.parse_document(html)
      assert Floki.find(document, "iframe") == []
    end

    test "setting the trip ID renders that trip", %{conn: conn, trip: trip} do
      {:ok, _, html} = live(conn, ~p"/admin/?#{[trip_id: trip.trip_id]}")
      {:ok, document} = Floki.parse_document(html)
      assert [_] = Floki.find(document, "iframe")
    end

    test "updating a trip updates the status", %{conn: conn, trip: trip, vehicle: vehicle} do
      {:ok, view, html} = live(conn, ~p"/admin")
      {:ok, document} = Floki.parse_document(html)
      assert [_] = elements = Floki.find(document, "#trips-#{trip.trip_id}")
      assert Floki.text(elements) =~ "enroute"

      Adept.set_vehicles([
        %{vehicle | timestamp: DateTime.utc_now(), last_arrived_trips: [trip.trip_id]}
      ])

      assert_receive {:vehicle_updated, _}

      html = render(view)
      {:ok, document} = Floki.parse_document(html)
      assert [_] = elements = Floki.find(document, "#trips-#{trip.trip_id}")
      assert Floki.text(elements) =~ "arrived"
    end

    test "closing a trip removes it from the page", %{conn: conn, trip: trip, vehicle: vehicle} do
      {:ok, view, html} = live(conn, ~p"/admin")
      {:ok, document} = Floki.parse_document(html)
      assert [_] = Floki.find(document, "#trips-#{trip.trip_id}")

      Adept.set_trips([
        %{trip | dropoff_performed?: true}
      ])

      Adept.set_vehicles([
        %{vehicle | timestamp: DateTime.utc_now()}
      ])

      assert_receive {:vehicle_updated, _}

      html = render(view)
      {:ok, document} = Floki.parse_document(html)
      assert [] = Floki.find(document, "#trips-#{trip.trip_id}")
    end

    test "updating a future trip doesn't add it back to the page", %{
      conn: conn,
      trip: trip,
      vehicle: vehicle
    } do
      Adept.set_trips([
        %{
          trip
          | trip_id: trip.trip_id + 1,
            promise_time: nil
        },
        trip
      ])

      {:ok, view, html} = live(conn, ~p"/admin")
      {:ok, document} = Floki.parse_document(html)
      assert [_] = Floki.find(document, "#trips tr")

      Adept.set_vehicles([%{vehicle | timestamp: DateTime.utc_now()}])
      assert_receive {:vehicle_updated, _}

      html = render(view)
      {:ok, document} = Floki.parse_document(html)
      assert [_] = Floki.find(document, "#trips tr")
    end
  end

  def login(%{conn: conn}) do
    conn =
      init_test_session(conn, %{
        logout_url: "url",
        roles: ["admin"],
        expires_at: System.system_time(:second) + 30
      })

    {:ok, conn: conn}
  end

  def adept(_) do
    trip = Fixtures.trip_fixture()
    vehicle = Fixtures.vehicle_fixture()
    Adept.set_trips([trip])
    Adept.set_vehicles([vehicle])
    RideAlong.PubSub.subscribe("vehicle:all")

    on_exit(fn ->
      Adept.set_trips([])
      Adept.set_vehicles([])
    end)

    {:ok, trip: trip, vehicle: vehicle}
  end
end
