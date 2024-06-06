defmodule RideAlong.OpenRouteServiceTest do
  @moduledoc false

  use ExUnit.Case, async: true
  alias RideAlong.OpenRouteService
  alias RideAlong.OpenRouteService.{Location, Route}

  describe "directions/2" do
    test "basic route response" do
      stub(fixture())
      destination = %Location{lat: 42.3516728, lon: -71.0718109}
      source = %Location{lat: 42.3516768, lon: -71.0695149}
      assert {:ok, %Route{} = route} = OpenRouteService.directions(source, destination)
      assert route.bearing == 255
    end

    test "handles a summary without a distance" do
      body = fixture()
      [route | _] = body["routes"]
      route = %{route | "summary" => Map.delete(route["summary"], "distance")}
      body = Map.put(body, "routes", [route])
      stub(body)

      destination = %Location{lat: 42.3516728, lon: -71.0718109}
      source = %Location{lat: 42.3516768, lon: -71.0695149}
      assert {:ok, %Route{}} = OpenRouteService.directions(source, destination)
    end
  end

  def fixture do
    %{
      "bbox" => [-71.073062, 42.350431, -71.069449, 42.351597],
      "metadata" => %{
        "attribution" => "openrouteservice.org, OpenStreetMap contributors, tmc - BASt",
        "engine" => %{
          "build_date" => "2024-05-14T12:55:19Z",
          "graph_date" => "2024-05-22T00:18:56Z",
          "version" => "8.0.1"
        },
        "id" => "vU6vc6nR5KJt-sEJ9KpHIA",
        "query" => %{
          "coordinates" => [[-71.0695149, 42.3516768], [-71.0718109, 42.3516728]],
          "format" => "json",
          "id" => "vU6vc6nR5KJt-sEJ9KpHIA",
          "profile" => "driving-car",
          "units" => "mi"
        },
        "service" => "routing",
        "timestamp" => 1_716_342_100_397
      },
      "routes" => [
        %{
          "bbox" => [-71.073062, 42.350431, -71.069449, 42.351597],
          "geometry" => "ywnaG`wwpLNjAFPz@hAz@|EbAzFcA^_Bn@eAaG",
          "segments" => [
            %{
              "distance" => 0.314,
              "duration" => 57.1,
              "steps" => [
                %{
                  "distance" => 0.184,
                  "duration" => 31.9,
                  "instruction" => "Head west on Park Plaza",
                  "maneuver" => %{
                    "bearing_after" => 255,
                    "bearing_before" => 0,
                    "location" => [-71.069449, 42.351488]
                  },
                  "name" => "Park Plaza",
                  "type" => 11,
                  "way_points" => [0, 5]
                }
              ]
            }
          ],
          "summary" => %{"distance" => 0.314, "duration" => 57.1},
          "way_points" => [0, 8]
        }
      ]
    }
  end

  def stub(body) do
    Req.Test.stub(RideAlong.OpenRouteService, fn conn ->
      Req.Test.json(conn, body)
    end)

    :ok
  end
end
