defmodule RideAlong.Adept.Trip do
  @moduledoc """
  Represents the Trip data coming from Adept.

  A Trip is a single pickup for a person.
  """
  @derive Jason.Encoder
  defstruct [
    :trip_id,
    :route_id,
    :date,
    # :last_name,
    # :first_name,
    :lat,
    :lon,
    :house_number,
    :address1,
    :address2,
    :city,
    :phone,
    :performed_at
  ]
end
