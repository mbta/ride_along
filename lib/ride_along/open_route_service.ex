defmodule RideAlong.OpenRouteService do
  @moduledoc """
  Interface to the OpenRouteService API.

  Currently, we're using this to calculate the route between a vehicle and the
  destination, along with the ETA (based on the latest GPS ping and the travel
  time).
  """

  defmodule Location do
    @moduledoc """
    Struct representing a location to query (either source or destination).

    Mostly so that clients don't need to remember the order of latitude/longitude.
    """
    defstruct [:lat, :lon]
  end

  defmodule Route do
    @moduledoc """
    A single route returned from the OpenRouteServiceAPI.
    """
    defstruct [
      :timestamp,
      :bbox,
      :source,
      :destination,
      :polyline,
      :bearing,
      :distance,
      :duration
    ]
  end

  def directions(source, destination) do
    query =
      %{
        maneuvers: true,
        continue_straight: true,
        units: "mi",
        coordinates: [
          [source.lon, source.lat],
          [destination.lon, destination.lat]
        ]
      }

    case Req.post(req(), url: "/ors/v2/directions/driving-car", json: query) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, parse_response(body)}

      {:ok, response} ->
        {:error, response}

      {:error, _} = error ->
        error
    end
  end

  defp req do
    Req.new(Application.get_env(:ride_along, __MODULE__)[:req_config])
  end

  defp parse_response(body) do
    %{
      "metadata" => %{
        "timestamp" => timestamp_ms,
        "query" => %{
          "coordinates" => [
            [source_lon, source_lat],
            [destination_lon, destination_lat]
          ]
        }
      },
      "routes" => [
        %{
          "summary" => %{
            "distance" => distance,
            "duration" => duration
          },
          "segments" => [
            %{
              "steps" => [
                %{
                  "maneuver" => %{
                    "bearing_after" => bearing
                  }
                }
                | _
              ]
            }
            | _
          ],
          "bbox" => [bbox_lon1, bbox_lat1, bbox_lon2, bbox_lat2],
          "geometry" => polyline
        }
        | _
      ]
    } = body

    %__MODULE__.Route{
      timestamp: DateTime.from_unix!(timestamp_ms, :millisecond),
      bbox:
        {%__MODULE__.Location{lat: bbox_lat1, lon: bbox_lon1},
         %__MODULE__.Location{lat: bbox_lat2, lon: bbox_lon2}},
      source: %__MODULE__.Location{lat: source_lat, lon: source_lon},
      destination: %__MODULE__.Location{lat: destination_lat, lon: destination_lon},
      bearing: bearing,
      polyline: polyline,
      distance: distance,
      duration: duration * Application.get_env(:ride_along, __MODULE__)[:duration_scale]
    }
  end
end
