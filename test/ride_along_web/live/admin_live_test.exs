defmodule RideAlongWeb.AdminLiveTest do
  @moduledoc false
  use RideAlongWeb.ConnCase, async: false

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
    Adept.set_trips([trip])
    Adept.set_vehicles([Fixtures.vehicle_fixture()])

    on_exit(fn ->
      Adept.set_trips([])
      Adept.set_vehicles([])
    end)

    {:ok, trip: trip}
  end
end
