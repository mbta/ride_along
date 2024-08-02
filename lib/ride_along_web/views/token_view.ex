defmodule RideAlongWeb.TokenView do
  use JSONAPI.View, type: "token"

  def fields do
    [:url, :status, :promise_time, :eta_time]
  end

  def relationships do
    [vehicle: RideAlongWeb.VehicleView]
  end
end
