defmodule RideAlong.EtaMonitor do
  @moduledoc """
  Watches all the trips and calculates ETAs.

  We do this in order to better understand how ETAs change over time, and the
  ADEPT ETAs (pick time) compare to the ORS calculated ETAs.
  """
  use GenServer
  require Logger

  require Explorer.DataFrame, as: DF
  alias RideAlong.Adept
  alias RideAlong.EtaCalculator.Training

  @default_name __MODULE__
  def start_link(opts) do
    if opts[:start] do
      name = Keyword.get(opts, :name, @default_name)
      GenServer.start_link(__MODULE__, name, name: name)
    else
      :ignore
    end
  end

  defstruct [:name, trip_date_to_key: %{}, trip_predictions: %{}]

  @type trip_date :: {Adept.Trip.id(), Date.t()}
  @type key :: {pick_time :: DateTime.t(), status :: Adept.Trip.status()}

  @impl GenServer
  def init(name) do
    :timer.send_interval(86_400_000, :clean_state)
    state = update_trips(%__MODULE__{name: name})
    RideAlong.PubSub.subscribe("trips:updated")
    RideAlong.PubSub.subscribe("vehicle:all")

    :net_kernel.monitor_nodes(true)

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:trips_updated, state) do
    state = update_trips(state)

    {:noreply, state}
  end

  def handle_info({:vehicle_updated, v}, state) do
    trips = Adept.get_trips_by_route(v.route_id)
    state = update_trips(state, trips)

    {:noreply, state}
  end

  def handle_info(:clean_state, state) do
    state = clean_state(state)

    {:noreply, state}
  end

  def handle_info({:nodeup, node}, state) do
    Process.send({state.name, node}, {:request_state, self()}, [:noconnect])

    {:noreply, state}
  end

  def handle_info({:nodedown, _node}, state) do
    {:noreply, state}
  end

  def handle_info({:request_state, pid}, state) do
    Process.send(pid, {:state_response, {self(), node()}, state}, [])

    {:noreply, state}
  end

  def handle_info({:state_response, from, remote_state}, state) do
    state =
      clean_state(%{
        state
        | trip_date_to_key:
            Map.merge(Map.get(remote_state, :trip_date_to_key, %{}), state.trip_date_to_key),
          trip_predictions:
            Map.merge(
              Map.get(remote_state, :trip_predictions, %{}),
              state.trip_predictions,
              fn _key, l1, l2 ->
                Enum.uniq(l1 ++ l2)
              end
            )
      })

    Logger.info("#{__MODULE__} received state update from #{inspect(from)}")
    {:noreply, state}
  end

  def clean_state(state, today \\ Date.utc_today()) do
    two_days_ago = Date.add(today, -2)

    date_filter = fn {{_, date}, _} ->
      Date.after?(date, two_days_ago)
    end

    trip_date_to_key =
      Map.filter(state.trip_date_to_key, date_filter)

    trip_predictions = Map.filter(state.trip_predictions, date_filter)

    %{state | trip_date_to_key: trip_date_to_key, trip_predictions: trip_predictions}
  end

  def update_trips(state, trips \\ Adept.all_trips(), now \\ DateTime.utc_now()) do
    trips
    |> Enum.sort(Adept.Trip)
    |> Enum.reduce(state, &update_trip(&2, &1, now))
  end

  def update_trip(state, trip, now) do
    vehicle = Adept.get_vehicle_by_route(trip.route_id)
    status = Adept.Trip.status(trip, vehicle, now)
    trip_date = {trip.trip_id, trip.date}

    new_key = {trip.route_id, trip.pick_time, status}

    {old_key, state} =
      get_and_update_in(state.trip_date_to_key[trip_date], fn old_key ->
        {old_key, new_key}
      end)

    changed? = new_key != old_key

    cond do
      status == :closed ->
        remove_trip_date_from_state(state, trip_date)

      changed? or status in [:enroute, :waiting] ->
        log = log_trip_status_change(trip, vehicle, status, now)
        update_accuracy_metrics(state, trip_date, log)

      true ->
        state
    end
  end

  defp remove_trip_date_from_state(state, trip_date) do
    %{
      state
      | trip_date_to_key: Map.delete(state.trip_date_to_key, trip_date),
        trip_predictions: Map.delete(state.trip_predictions, trip_date)
    }
  end

  def log_trip_status_change(trip, vehicle, status, now) do
    {route, route_metadata} = route_metadata(status, trip, vehicle)

    log =
      basic_metadata(trip, vehicle, status, now) ++
        vehicle_metadata(vehicle) ++
        route_metadata ++ calculated_metadata(status, trip, vehicle, route, now)

    if RideAlong.Singleton.singleton?() do
      Logster.info(log)
    end

    log
  end

  defp basic_metadata(trip, vehicle, status, now) do
    location_timestamp =
      if vehicle do
        vehicle.timestamp
      else
        nil
      end

    [
      module: __MODULE__,
      log: :monitor,
      trip_id: trip.trip_id,
      route: trip.route_id,
      client_id: trip.client_id,
      status: status,
      trip_status: trip.status,
      promise: trip.promise_time,
      pick: trip.pick_time,
      pick_order: trip.pick_order,
      pick_lat: trip.lat,
      pick_lon: trip.lon,
      client_trip_index: trip.client_trip_index,
      time: location_timestamp || now,
      location: location_timestamp,
      load_time: trip.load_time,
      pickup_performed?: trip.pickup_performed?,
      dropoff_performed?: trip.dropoff_performed?,
      pickup_arrival: trip.pickup_arrival_time
    ]
  end

  defp vehicle_metadata(%{} = vehicle) do
    [
      vehicle_lat: vehicle.lat,
      vehicle_lon: vehicle.lon,
      vehicle_heading: vehicle.heading,
      vehicle_speed: vehicle.speed,
      last_pick: vehicle.last_pick,
      last_drop: vehicle.last_drop,
      last_arrived: inspect(vehicle.last_arrived_trips)
    ]
  end

  defp vehicle_metadata(nil) do
    []
  end

  defp route_metadata(status, trip, %{} = vehicle) when status in [:enroute, :waiting] do
    case RideAlong.OpenRouteService.directions(vehicle, trip) do
      {:ok, route} ->
        ors_eta =
          if vehicle.timestamp do
            DateTime.add(vehicle.timestamp, trunc(route.duration * 1000), :millisecond)
          else
            nil
          end

        {route,
         [
           ors_duration: route.duration,
           ors_heading: route.bearing,
           ors_distance: route.distance,
           ors_eta: ors_eta
         ]}

      {:error, _reason} ->
        {nil, []}
    end
  end

  defp route_metadata(_status, _trip, _vehicle) do
    {nil, []}
  end

  defp calculated_metadata(status, trip, vehicle, route, now)
       when status in [:enroute, :waiting] do
    {msec, calculated} =
      :timer.tc(
        RideAlong.EtaCalculator,
        :calculate,
        [trip, vehicle, route, now],
        :millisecond
      )

    [calculated: calculated, calculated_ms: msec]
  end

  defp calculated_metadata(_status, _trip, _vehicle, _route, _now) do
    []
  end

  def update_accuracy_metrics(state, trip_date, log) do
    trip_predictions = state.trip_predictions
    time = log[:time]
    route_id = log[:route]

    trip_predictions =
      case log[:status] do
        s when s in [:enroute, :waiting] ->
          pick = log[:pick]
          calculated = log[:calculated]
          record = {time, route_id, pick, calculated}
          Map.update(trip_predictions, trip_date, [record], &[record | &1])

        :arrived ->
          {predictions, trip_predictions} = Map.pop(trip_predictions, trip_date, [])

          predictions =
            for {prediction_time, ^route_id, pick, calculated} <- predictions do
              %{
                arrival_time: shift_to_utc!(time),
                time: shift_to_utc!(prediction_time),
                pick: shift_to_utc!(pick),
                calculated: shift_to_utc!(calculated)
              }
            end

          if RideAlong.Singleton.singleton?() and predictions != [] do
            predictions
            |> DF.new()
            |> grouped_accuracy_rows()
            |> Enum.each(fn row ->
              Logster.info(
                module: __MODULE__,
                log: :accuracy,
                trip_id: log[:trip_id],
                route: route_id,
                field: row["field"],
                category: inspect(row["category"]),
                size: row["size"],
                accurate_count: row["accurate_count"],
                early_count: row["early_count"],
                late_count: row["late_count"]
              )
            end)
          end

          trip_predictions

        :picked_up ->
          Map.delete(trip_predictions, trip_date)

        _ ->
          trip_predictions
      end

    %{state | trip_predictions: trip_predictions}
  end

  defp shift_to_utc!(nil), do: nil

  defp shift_to_utc!(%DateTime{} = dt) do
    DateTime.shift_zone!(dt, "Etc/UTC")
  end

  @spec grouped_accuracy_rows(DF.t()) :: [map()]
  defp grouped_accuracy_rows(df) do
    Enum.flat_map([:pick, :calculated], fn field ->
      df
      |> Training.grouped_accuracy(:time, :arrival_time, field, &Training.accuracy/1)
      |> DF.mutate(field: ^"#{field}")
      |> DF.to_rows()
    end)
  end

  @dialyzer {:nowarn_function, grouped_accuracy_rows: 1}
end
