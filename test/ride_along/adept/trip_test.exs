defmodule RideAlong.Adept.TripTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias RideAlong.Adept.Trip

  describe "address/1" do
    test "returns an binary for the trip" do
      check all(t <- trip()) do
        assert is_binary(Trip.address(t))
      end
    end
  end

  defp trip do
    gen all(
          house_number <- nullable_string(:ascii),
          address1 <- string(:ascii),
          address2 <- nullable_string(:ascii),
          city <- string(:ascii),
          state <- nullable_string(:ascii),
          zip <- nullable_string(:ascii)
        ) do
      %Trip{
        house_number: house_number,
        address1: address1,
        address2: address2,
        city: city,
        state: state,
        zip: zip
      }
    end
  end

  defp nullable_string(kind) do
    one_of([constant(nil), string(kind)])
  end
end
