defmodule RideAlong.LinkShortenerTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties

  import RideAlong.LinkShortener

  alias RideAlong.Adept.Trip

  describe "generate_token_map/1" do
    test "generates unique tokens for all trips" do
      check all(trips <- list_of_trips()) do
        token_map = generate_token_map(trips)

        assert map_size(token_map) == length(trips)
      end
    end
  end

  defp list_of_trips do
    {:ok, initial_date} = Date.new(2024, 1, 1)

    sized(fn size ->
      length = size * 10

      gen all(
            trip_ids <- uniq_list_of(resize(integer(), size * 1000), length: length),
            days <- list_of(integer(-10..10), length: length)
          ) do
        for {trip_id, day} <- Enum.zip(trip_ids, days) do
          %Trip{
            trip_id: trip_id,
            date: Date.add(initial_date, day)
          }
        end
      end
    end)
  end
end
