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
    state =
      if RideAlong.Singleton.singleton?() do
        update_trips(state)
      else
        state
      end

    {:noreply, state}
  end

  def handle_info({:vehicle_updated, v}, state) do
    state =
      if RideAlong.Singleton.singleton?() do
        trips = Adept.get_trips_by_route(v.route_id)
        update_trips(state, trips)
      else
        state
      end

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
    state = %{
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
    }

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
    old_key = Map.get(state.trip_date_to_key, trip_date, new_key)

    state = put_in(state.trip_date_to_key[trip_date], new_key)

    changed? = new_key != old_key

    state =
      if status != :closed and (changed? or status in [:enroute, :waiting]) do
        log = log_trip_status_change(trip, vehicle, status, now)
        update_accuracy_metrics(state, trip_date, log)
      else
        state
      end

    state
  end

  def log_trip_status_change(trip, vehicle, status, now) do
    location_timestamp =
      if vehicle do
        vehicle.timestamp
      else
        nil
      end

    basic_metadata = [
      module: __MODULE__,
      log: :monitor,
      trip_id: trip.trip_id,
      route: trip.route_id,
      status: status,
      promise: trip.promise_time,
      pick: trip.pick_time,
      pick_order: trip.pick_order,
      pick_lat: trip.lat,
      pick_lon: trip.lon,
      client_trip_index: trip.client_trip_index,
      time: location_timestamp || now,
      location: location_timestamp,
      load_time: trip.load_time,
      pickup_arrival: trip.pickup_arrival_time
    ]

    vehicle_metadata =
      with true <- status in [:enroute, :waiting],
           %{} <- vehicle do
        [
          vehicle_lat: vehicle.lat,
          vehicle_lon: vehicle.lon,
          vehicle_heading: vehicle.heading,
          vehicle_speed: vehicle.speed
        ]
      else
        _ -> []
      end

    route =
      with true <- status in [:enroute, :waiting],
           %{} <- vehicle,
           {:ok, route} <- RideAlong.OpenRouteService.directions(vehicle, trip) do
        route
      else
        _ -> nil
      end

    route_metadata =
      if route do
        ors_eta =
          if vehicle.timestamp do
            DateTime.add(vehicle.timestamp, trunc(route.duration * 1000), :millisecond)
          else
            nil
          end

        [
          ors_duration: route.duration,
          ors_heading: route.bearing,
          ors_distance: route.distance,
          ors_eta: ors_eta
        ]
      else
        []
      end

    calculated_metadata =
      if status in [:enroute, :waiting] do
        {msec, calculated} =
          :timer.tc(
            RideAlong.EtaCalculator,
            :calculate,
            [trip, vehicle, route, now],
            :millisecond
          )

        [calculated: calculated, calculated_ms: msec]
      else
        []
      end

    log = basic_metadata ++ vehicle_metadata ++ route_metadata ++ calculated_metadata

    Logster.info(log)

    log
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
              %{arrival_time: time, time: prediction_time, pick: pick, calculated: calculated}
            end

          if predictions != [] do
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
