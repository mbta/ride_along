defmodule RideAlong.RouteCacheTest do
  @moduledoc false
  use ExUnit.Case

  alias RideAlong.OpenRouteService.{Location, Route}
  alias RideAlong.OpenRouteServiceFixtures, as: ORSFixtures
  alias RideAlong.RouteCache

  @polyline "q}maGpbvpLF?fAAv@Bp@HD@`AXHBvAb@xDlA\\JlA`@fC~@bA`@fA`@x@ZjAb@hE~Aj@Th@`@`@`@l@p@^h@lAnB`@p@p@r@hCbEtAvBpApBvAzBFH~AhC`AxA"
  @location %Location{lon: -71.06117, lat: 42.34639, heading: 180.0}

  describe "directions/2" do
    setup do
      destination = %Location{
        lat: 42 + :rand.uniform_real(),
        lon: -71 - :rand.uniform_real()
      }

      {:ok, destination: destination}
    end

    test "returns a cached value if the source/destination are the same both times", %{
      destination: destination
    } do
      ORSFixtures.stub(ORSFixtures.fixture())

      assert {:ok, %Route{} = original} = RouteCache.directions(@location, destination)

      ORSFixtures.stub(:not_found, %{})

      assert {:ok, ^original} = RouteCache.directions(@location, destination)
    end

    test "returns an error if an un-cached result is an error", %{destination: destination} do
      ORSFixtures.stub(:not_found, %{})

      assert {:error, _} = RouteCache.directions(@location, destination)
    end
  end

  describe "snap_to_polyline/2" do
    test "snaps a point to the polyline if it's close" do
      snapped = RouteCache.snap_to_polyline(@location, @polyline)

      assert_in_delta snapped.lon, -71.06112, 0.0001
      assert_in_delta snapped.lat, 42.34633, 0.0001
      assert snapped.heading == @location.heading
    end

    test "uses the original point if it's not close to the polyline" do
      location = %Location{lat: 42.3465, lon: -71.06181, heading: 90.0}

      snapped = RouteCache.snap_to_polyline(location, @polyline)

      assert snapped == location
    end
  end
end
