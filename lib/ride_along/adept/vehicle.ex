defmodule RideAlong.Adept.Vehicle do
  @moduledoc """
  Represents the Vehicle data coming from Adept.

  A vehicle has an ID, a location, and a last-updated timestamp.
  """
  @derive Jason.Encoder
  defstruct [
    :vehicle_id,
    :lat,
    :lon,
    :timestamp
  ]
end
