defmodule RideAlong.SqlParserTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias RideAlong.SqlParser

  describe "local_timestamp/2" do
    test "always returns a value in the given timezone" do
      time_zone = "America/New_York"

      for month <- 1..12,
          day <- 1..28,
          hour <- 0..23,
          {month, day, hour} != {3, 10, 2} do
        dt = SqlParser.local_timestamp({{2024, month, day}, {hour, 30, 5, 100}}, time_zone)

        assert %DateTime{
                 year: 2024,
                 month: ^month,
                 day: ^day,
                 hour: ^hour,
                 minute: 30,
                 second: 5,
                 microsecond: {100, 3},
                 time_zone: ^time_zone
               } = dt
      end
    end
  end
end
