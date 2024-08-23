defmodule RideAlong.SqlPublisher do
  @moduledoc """
  Periodically runs SQL queries (via Tds) and sends the output to MQTT topics.
  """
  use GenServer
  require Logger

  alias EmqttFailover.Message
  alias RideAlong.MqttConnection

  @default_name __MODULE__
  def start_link(opts) do
    if opts[:start] do
      name = Keyword.get(opts, :name, @default_name)
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      :ignore
    end
  end

  defstruct [:tds, :connection, topic_prefix: "", results: %{}]

  @impl GenServer
  def init(_opts) do
    state = %__MODULE__{}
    {:ok, state, {:continue, :start_timers}}
  end

  @impl GenServer
  def handle_continue(:start_timers, state) do
    results =
      for {name, config} <- queries(), into: %{} do
        :timer.send_interval(config.interval, {:query, name})
        send(self(), {:query, name})
        {name, []}
      end

    {:noreply, %{state | results: results}, {:continue, :connect}}
  end

  def handle_continue(:connect, state) do
    app_config = Application.get_env(:ride_along, __MODULE__)
    {:ok, tds} = Tds.start_link(app_config[:database])
    {:ok, connection} = MqttConnection.start_link()

    state = %{
      state
      | tds: tds,
        connection: connection,
        topic_prefix: MqttConnection.topic_prefix()
    }

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:query, name}, state) do
    query = queries()[name]
    sql = query.sql
    parameters = Map.get(query, :parameters, [])

    case tds_query(state.tds, sql, parameters) do
      {:ok, results} ->
        Logger.info("#{__MODULE__} query success name=#{name} results=#{length(results)}")
        Logger.debug("#{__MODULE__} query result name=#{name} results=#{inspect(results)}")
        state = put_in(state.results[name], results)
        publish(state, name)
        {:noreply, state}

      {:error, reason} ->
        Logger.info("#{__MODULE__} query failed name=#{name} reason=#{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info({:connected, connection}, %{connection: connection} = state) do
    for name <- Map.keys(state.results) do
      publish(state, name)
    end

    {:noreply, state}
  end

  def handle_info({:disconnected, _, _reason}, state) do
    {:noreply, state}
  end

  defp tds_query(tds, sql, parameters) do
    parameters =
      for {name, value} <- parameters do
        %Tds.Parameter{
          name: "@#{name}",
          value: value
        }
      end

    try do
      %{
        columns: columns,
        rows: rows
      } = Tds.query!(tds, sql, parameters)

      mapped =
        for row <- rows do
          columns
          |> Enum.zip(row)
          |> Map.new()
        end

      {:ok, mapped}
    rescue
      e ->
        {:error, e}
    end
  end

  defp queries do
    service_date =
      DateTime.utc_now()
      |> DateTime.add(-3, :hour)
      |> DateTime.shift_zone!(Application.get_env(:ride_along, :time_zone))
      |> DateTime.to_date()
      |> Date.to_iso8601()

    # Route vehicle designations:
    # https://trac.zendesk.com/hc/en-us/articles/4409591371284-Route-Vehicle-Designations
    # 10_000s: DSP
    # 200_000s: DSP replacement route
    # 300_000s: DSP new routes for added drivers
    # 400_000s: FLEX
    # 500_000s: FLEX
    # 600_000s: NDSP
    # 700_000s: NDSP
    %{
      trips: %{
        sql: ~s[WITH Trips AS (
              SELECT *,
              ROW_NUMBER() OVER (PARTITION BY ClientId ORDER BY ClientId, TripDate) AS ClientTripIndex
              FROM dbo.TRIP
             )
             SELECT Id, TripDate, RouteId,
             ClientId, ClientTripIndex,
             Status, Anchor, PickTime, PromiseTime,
             PickHouseNumber, PickAddress1, PickAddress2, PickCity, PickSt, PickZip,
             PickGridX, PickGridY,
             PickOrder, DropOrder, PerformPickup, PerformDropoff, LoadTime
             FROM Trips t
             WHERE
               t.TripDate = @service_date AND
               PickGridX != 0 AND PickGridY != 0 AND
               ClientId > 0 AND
               (RouteId < 400000 OR RouteId >= 800000)],
        parameters: %{service_date: service_date},
        interval: 300_000
      },
      locations: %{
        sql: ~s[SELECT RouteId, VehicleId, Latitude, Longitude, Heading, LocationDate,
               COALESCE((SELECT MAX(PickOrder) FROM dbo.TRIP t
                 WHERE t.RouteId = l.RouteId AND t.TripDate = @service_date AND t.PerformPickup != 0), 1) AS LastPick,
               COALESCE((SELECT MAX(DropOrder) FROM dbo.TRIP t
                 WHERE t.RouteId = l.RouteId AND t.TripDate = @service_date AND t.PerformDropoff != 0), 1) AS LastDrop,
               (SELECT TOP 1 TripId FROM dbo.MDCVEHICLELOCATION
                 WHERE RouteId = l.RouteId AND LocationDate >= @service_date AND EventType='StopArrive'
                 ORDER BY LocationDate DESC) AS LastArrivedTrip,
               (SELECT TOP 1 t.Id FROM dbo.TRIP t
                 WHERE t.RouteId = l.RouteId AND t.TripDate = @service_date AND t.Status = 'S'
                 ORDER BY t.APtime1 DESC) AS LastDispatchArrivedTrip
                  FROM dbo.MDCVEHICLELOCATION l 
                  WHERE LocationDate >= @service_date AND 
                  LocationDate = (SELECT max(l1.LocationDate) from dbo.MDCVEHICLELOCATION l1 where l1.RouteId = l.RouteId)
                  ORDER BY l.LocationDate DESC],
        parameters: %{service_date: service_date},
        interval: 5_000
      }
    }
  end

  defp publish(%{connection: connection} = state, name) when not is_nil(connection) do
    result = state.results[name]

    MqttConnection.publish(
      state.connection,
      %Message{
        topic: state.topic_prefix <> Atom.to_string(name),
        payload: :erlang.term_to_binary(result),
        qos: 1,
        retain?: true
      }
    )
  end
end
