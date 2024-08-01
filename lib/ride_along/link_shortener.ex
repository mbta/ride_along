defmodule RideAlong.LinkShortener do
  @moduledoc """
  Generates a secure tokens for each trip.

  We want to provide a short (8 character) token in our links, but in such
  a way that it's hard for an attacker to:
  - generate a valid token even if they know the underlying trip ID
  - iterate through tokens

  Implementation:
  - sort the trips by ID
  - for each trip, generate an initial token:
    - binary = :erlang.term_to_binary({SECRET_KEY_BASE, trip.date, trip.trip_id, 0})
    - hash = :crypto.hash(:sha3_224, binary)
    - short_bytes = :binary.part(hash, 0, 6)
    - short_b64 = Base.url_encode64(short_bytes)
    - if this process generates a hash value that's already been used:
      - increment the last digit by 1 until it does not generate a duplicate
  """
  use GenServer
  require Logger

  alias RideAlong.Adept.Trip

  @default_name __MODULE__

  def start_link(opts \\ []) do
    opts = Keyword.put_new(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, [], opts)
  end

  def get_token(name \\ @default_name, trip_id) when is_integer(trip_id) do
    GenServer.call(name, {:get_token, trip_id})
  end

  def get_trip(name \\ @default_name, token) when is_binary(token) do
    GenServer.call(name, {:get_trip, token})
  end

  defstruct [:token_map, :trip_id_map]

  @impl GenServer
  def init([]) do
    state = update_token_maps()
    Phoenix.PubSub.subscribe(RideAlong.PubSub, "trips:updated")

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:get_token, trip_id}, _from, state) do
    {:reply, Map.get(state.trip_id_map, trip_id), state}
  end

  def handle_call({:get_trip, token}, _from, state) do
    {:reply, Map.get(state.token_map, token), state}
  end

  @impl GenServer
  def handle_info(:trips_updated, _state) do
    state = update_token_maps()
    {:noreply, state}
  end

  def update_token_maps do
    token_map = generate_token_map(RideAlong.Adept.all_trips())
    trip_id_map = Map.new(token_map, fn {token, trip} -> {trip.trip_id, token} end)

    now = DateTime.utc_now()

    for {token, trip} <- Enum.sort_by(token_map, &elem(&1, 1), RideAlong.Adept.Trip),
        trip.pick_time != nil,
        trip.route_id > 0,
        not trip.pickup_performed?,
        not is_nil(RideAlong.Adept.get_vehicle_by_route(trip.route_id)) do
      diff = DateTime.diff(trip.pick_time, now)

      if diff > 0 and diff < 1_800 do
        IO.puts(
          "#{__MODULE__} generated short link route_id=#{trip.route_id} trip_id=#{trip.trip_id} token=#{token} pick_time=#{DateTime.to_iso8601(trip.pick_time)}"
        )
      end
    end

    %__MODULE__{
      token_map: token_map,
      trip_id_map: trip_id_map
    }
  end

  def generate_token_map(trips) do
    trips
    |> Enum.sort(Trip)
    |> Enum.reduce(%{}, &hash_trip/2)
  end

  def hash_trip(trip, link_map, index \\ 0) do
    binary = :erlang.term_to_binary({secret(), trip.date, trip.trip_id, index})
    hash = :crypto.hash(:sha3_224, binary)
    short_bytes = :binary.part(hash, 0, 6)
    short_b64 = Base.url_encode64(short_bytes)

    if Map.has_key?(link_map, short_b64) do
      hash_trip(trip, link_map, index + 1)
    else
      Map.put(link_map, short_b64, trip)
    end
  end

  defp secret do
    Application.get_env(:ride_along, __MODULE__)[:secret]
  end
end
