defmodule RideAlong.SqlParser do
  @moduledoc """
  Helper functions for parsing SQL data.
  """

  def local_timestamp(timestamp, timezone \\ Application.get_env(:ride_along, :time_zone)) do
    {{year, month, day}, {hour, minute, second, millisecond}} = timestamp
    date = Date.new!(year, month, day)
    time = Time.new!(hour, minute, second, {millisecond, 3})

    case DateTime.new(date, time, timezone) do
      {:ok, dt} ->
        dt

      {_, %DateTime{} = first, _} ->
        first
    end
  end
end
