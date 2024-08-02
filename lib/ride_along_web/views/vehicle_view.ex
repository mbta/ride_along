defmodule RideAlongWeb.VehicleView do
  use JSONAPI.View, type: "vehicle"

  def fields, do: [:heading, :lat, :lon, :timestamp]

  def id(vehicle) do
    vehicle.vehicle_id
  end
end
