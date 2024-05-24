defmodule RideAlong.LinkShortenerTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties

  import RideAlong.LinkShortener

  alias RideAlong.Adept.Trip

  describe "generate_token_map/1" do
    test "generates unique tokens for all trips" do
      check all(trips <- list_of(trip())) do
        token_map = generate_token_map(trips)

        assert map_size(token_map) == length(trips)
      end
    end
  end

  defp trip do
    {:ok, initial_date} = Date.new(2024, 1, 1)

    gen all(
          trip_id <- positive_integer(),
          days <- integer(-10..10)
        ) do
      date = Date.add(initial_date, days)

      %Trip{
        date: date,
        trip_id: trip_id
      }
    end
  end
end
