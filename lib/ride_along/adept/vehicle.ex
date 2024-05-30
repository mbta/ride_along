defmodule RideAlong.Adept.Vehicle do
  @moduledoc """
  Represents the Vehicle data coming from Adept.

  A vehicle has an ID, a location, and a last-updated timestamp.
  """
  @derive Jason.Encoder
  defstruct [
    :route_id,
    :vehicle_id,
    :lat,
    :lon,
    :timestamp,
    :last_pick,
    :last_drop
  ]

  def from_sql_map(map) do
    %{
      "RouteId" => route_id,
      "VehicleId" => vehicle_id,
      "Latitude" => lat,
      "Longitude" => lon,
      "LocationDate" => location_timestamp,
      "LastPick" => last_pick,
      "LastDrop" => last_drop
    } = map

    %__MODULE__{
      route_id: route_id,
      vehicle_id: vehicle_id,
      lat: lat,
      lon: lon,
      timestamp: RideAlong.SqlParser.local_timestamp(location_timestamp),
      last_pick: last_pick,
      last_drop: last_drop
    }
  end
end
