defmodule RideAlongWeb.Api.TripControllerTest do
  use RideAlongWeb.ConnCase

  alias RideAlong.Adept
  alias RideAlong.AdeptFixtures
  alias RideAlong.OpenRouteServiceFixtures

  describe "GET /api/trips/:trip_id" do
    setup do
      trip = AdeptFixtures.trip_fixture()
      Adept.set_trips([trip])

      OpenRouteServiceFixtures.stub(OpenRouteServiceFixtures.fixture())

      authorization = "Bearer testApiKey"
      path = ~p"/api/trips/#{trip.trip_id}"

      on_exit(fn ->
        Adept.set_trips([])
        Adept.set_vehicles([])
      end)

      {:ok, %{trip_id: trip.trip_id, path: path, authorization: authorization}}
    end

    test "401 Unauthorized without an API key", %{conn: conn, path: path} do
      conn = get(conn, path)
      assert json_response(conn, 401)
    end

    test "401 Unauthorized with an invalid API key", %{conn: conn, path: path} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid_key")
        |> get(path)

      assert json_response(conn, 401)
    end

    test "404 Not Found with an invalid trip_id", %{
      conn: conn,
      path: path,
      authorization: authorization
    } do
      Adept.set_trips([])

      conn =
        conn
        |> put_req_header("authorization", authorization)
        |> get(path)

      assert json_response(conn, 404)
    end

    test "200 OK with a valid trip", %{
      conn: conn,
      path: path,
      authorization: authorization,
      trip_id: trip_id
    } do
      conn =
        conn
        |> put_req_header("authorization", authorization)
        |> get(path)

      id = "#{trip_id}"

      assert %{
               "data" => %{
                 "id" => ^id,
                 "attributes" => %{
                   "status" => "ENQUEUED",
                   "pickupEta" => _,
                   "promiseTime" => _,
                   "url" => _
                 },
                 "relationships" => %{}
               }
             } = json_response(conn, 200)
    end

    test "200 OK with included vehicle/route", %{
      conn: conn,
      path: path,
      authorization: authorization,
      trip_id: trip_id
    } do
      %{vehicle_id: vehicle_id, route_id: route_id} = vehicle = AdeptFixtures.vehicle_fixture(%{})
      Adept.set_vehicles([vehicle])

      trip_id = "#{trip_id}"
      route_id = "#{route_id}"

      conn =
        conn
        |> put_req_header("authorization", authorization)
        |> get(path, %{"include" => "vehicle,route"})

      assert %{
               "data" => %{
                 "id" => ^trip_id,
                 "attributes" => %{},
                 "relationships" => %{
                   "vehicle" => %{"data" => %{"id" => ^vehicle_id}},
                   "route" => %{"data" => %{"id" => ^route_id}}
                 }
               },
               "included" => included
             } = json_response(conn, 200)

      assert Enum.any?(included, &match?(%{"type" => "vehicles", "id" => ^vehicle_id}, &1))
      assert Enum.any?(included, &match?(%{"type" => "routes", "id" => ^route_id}, &1))
    end
  end
end
