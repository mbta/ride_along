defmodule RideAlong.Adept.Vehicle do
  @moduledoc """
  Represents the Vehicle data coming from Adept.

  A vehicle has an ID, a location, and a last-updated timestamp.
  """
  @derive Jason.Encoder
  defstruct [
    :route_id,
    :vehicle_id,
    :heading,
    :lat,
    :lon,
    :timestamp,
    :last_pick,
    :last_drop,
    :last_arrived_trip
  ]

  @type t :: %__MODULE__{}

  @spec from_sql_map(%{binary() => term()}) :: t()
  def from_sql_map(map) do
    %{
      "RouteId" => route_id,
      "VehicleId" => vehicle_id,
      "Heading" => heading,
      "Latitude" => lat,
      "Longitude" => lon,
      "LocationDate" => location_timestamp,
      "LastPick" => last_pick,
      "LastDrop" => last_drop,
      "LastArrivedTrip" => last_arrived_trip
    } = map

    %__MODULE__{
      route_id: route_id,
      vehicle_id: vehicle_id,
      heading: heading,
      lat: lat,
      lon: lon,
      timestamp: RideAlong.SqlParser.local_timestamp(location_timestamp),
      last_pick: last_pick,
      last_drop: last_drop,
      last_arrived_trip: last_arrived_trip
    }
  end
end
