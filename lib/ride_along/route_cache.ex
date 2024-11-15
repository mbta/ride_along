defmodule RideAlong.RouteCache do
  @moduledoc """
  Module to cache results from RideAlong.OpenRouteService. This has two benefits:
  - fewer requests, as both EtaMonitor and TripLive.Show can share results
  - we can use the previous result to snap incoming points to the previous route (if it's close enough)

  The snapping is most useful in downtown, as there are many roads and it's easy
  for a slightly incorrect GPS ping to result in a very different routing.
  """
  import Cachex.Spec

  alias RideAlong.OpenRouteService
  alias RideAlong.OpenRouteService.Location

  @default_name __MODULE__
  # 10 meters
  @snap_allowed_distance 0.01

  def start_link(opts \\ []) do
    name = opts[:name] || @default_name

    Cachex.start_link(name,
      expiration: expiration(default: :timer.minutes(5))
    )
  end

  def child_spec(opts \\ []) do
    %{
      id: opts[:name] || @default_name,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def directions(name \\ @default_name, source, destination) do
    vehicle_id = Map.get(source, :vehicle_id)
    source = Map.take(source, [:lat, :lon, :heading])
    destination = Map.take(destination, [:lat, :lon])

    key = {source, destination}

    keys =
      if vehicle_id do
        [{vehicle_id, destination}, key]
      else
        [key]
      end

    Cachex.transaction!(name, keys, &directions_transaction(&1, vehicle_id, source, destination))
  end

  defp directions_transaction(cache, vehicle_id, source, destination) do
    old_polyline = Cachex.get!(cache, {vehicle_id, destination})

    source =
      if old_polyline do
        snap_to_polyline(source, old_polyline)
      else
        source
      end

    result =
      Cachex.fetch!(cache, {source, destination}, fn _ ->
        case OpenRouteService.directions(source, destination) do
          {:ok, route} -> {:commit, {:ok, route}}
          {:error, _} = error -> {:ignore, error}
        end
      end)

    case result do
      {:ok, route} when vehicle_id != nil ->
        Cachex.put!(cache, {vehicle_id, destination}, route.polyline)

      _ ->
        :ok
    end

    result
  end

  def snap_to_polyline(location, polyline, opts \\ []) do
    %{lat: lat0, lon: lon0} = location
    allowed_distance = Keyword.get(opts, :allowed_distance, @snap_allowed_distance)
    points = Polyline.decode(polyline)

    {_distance, snapped} =
      points
      |> Enum.zip(tl(points))
      |> Enum.reduce({allowed_distance, location}, fn {{lon1, lat1}, {lon2, lat2}},
                                                      {distance, _} =
                                                        acc ->
        d_lat = lat2 - lat1
        d_lon = lon2 - lon1
        dot = (lon0 - lon1) * d_lat + (lat0 - lat1) * d_lon

        t =
          if d_lat != 0 or d_lon != 0 do
            dot / (d_lat ** 2 + d_lon ** 2)
          else
            -1
          end

        new_point =
          cond do
            t > 1 -> {lat2, lon2}
            t > 0 -> {lat1 + d_lat * t, lon1 + d_lon * t}
            true -> {lat1, lon1}
          end

        new_distance = :vincenty.distance({lat0, lon0}, new_point)

        if new_distance < distance do
          {lat, lon} = new_point
          {new_distance, %Location{lat: lat, lon: lon, heading: Map.get(location, :heading)}}
        else
          acc
        end
      end)

    snapped
  end
end
