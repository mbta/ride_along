defmodule RideAlongWeb.TripView do
  use JSONAPI.View, type: "trips"

  def fields do
    [:url, :status, :promise_time, :pickup_eta]
  end

  def relationships do
    [vehicle: RideAlongWeb.VehicleView, route: RideAlongWeb.RouteView]
  end
end
