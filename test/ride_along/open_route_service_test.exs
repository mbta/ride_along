defmodule RideAlong.OpenRouteServiceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias RideAlong.OpenRouteService
  alias RideAlong.OpenRouteService.Location
  alias RideAlong.OpenRouteService.Route
  alias RideAlong.OpenRouteServiceFixtures, as: Fixtures

  describe "directions/2" do
    test "basic route response" do
      Fixtures.stub(Fixtures.fixture())
      destination = %Location{lat: 42.3516728, lon: -71.0718109}
      source = %Location{lat: 42.3516768, lon: -71.0695149}
      assert {:ok, %Route{} = route} = OpenRouteService.directions(source, destination)
      assert route.heading == 255
    end

    test "handles a summary without a distance" do
      body = Fixtures.fixture()
      [route | _] = body["routes"]
      route = %{route | "summary" => Map.delete(route["summary"], "distance")}
      body = Map.put(body, "routes", [route])
      Fixtures.stub(body)

      destination = %Location{lat: 42.3516728, lon: -71.0718109}
      source = %Location{lat: 42.3516768, lon: -71.0695149}
      assert {:ok, %Route{}} = OpenRouteService.directions(source, destination)
    end

    test "handles a route not found error" do
      body = %{
        "error" => %{
          "code" => 2009,
          "message" => "Route could not be found - Unable to find a route between points 1 (XXX XXX) and 2 (XXX XXX)."
        }
      }

      Fixtures.stub(404, body)

      destination = %Location{lat: 42.3516728, lon: -71.0718109}
      source = %Location{lat: 42.3516768, lon: -71.0695149}
      assert {:error, {:route_not_found, _}} = OpenRouteService.directions(source, destination)
    end
  end
end
