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
    :state,
    :zip,
    :phone,
    :performed_at
  ]

  def address(%__MODULE__{} = trip) do
    street =
      [
        trip.house_number,
        trip.address1,
        trip.address2
      ]
      |> Enum.reject(&(&1 in ["", nil]))
      |> Enum.intersperse(" ")

    Enum.join(
      [
        street,
        trip.city,
        trip.state || "MA"
      ],
      ", "
    )
  end

  def compare(%__MODULE__{} = a, %__MODULE__{} = b) do
    date_compare = Date.compare(a.date, b.date)

    cond do
      date_compare != :eq ->
        date_compare

      a.trip_id < b.trip_id ->
        :lt

      a.trip_id > b.trip_id ->
        :gt

      true ->
        :eq
    end
  end
end
