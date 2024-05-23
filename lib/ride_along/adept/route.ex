defmodule RideAlong.Adept.Route do
  @moduledoc """
  Represents the Route data coming from Adept.

  A route is a driver and a vehicle.
  """
  @derive Jason.Encoder
  defstruct [
    :route_id,
    :driver_name,
    :vehicle_id
  ]
end
