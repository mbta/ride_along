defmodule RideAlongWeb.RouteView do
  use JSONAPI.View, type: "routes"

  def fields, do: [:id]
end
