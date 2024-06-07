defmodule RideAlong.OpenRouteServiceTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias RideAlong.OpenRouteService
  alias RideAlong.OpenRouteServiceFixtures, as: Fixtures
  alias RideAlong.OpenRouteService.{Location, Route}

  describe "directions/2" do
    test "basic route response" do
      Fixtures.stub(Fixtures.fixture())
      destination = %Location{lat: 42.3516728, lon: -71.0718109}
      source = %Location{lat: 42.3516768, lon: -71.0695149}
      assert {:ok, %Route{} = route} = OpenRouteService.directions(source, destination)
      assert route.bearing == 255
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
  end
end
