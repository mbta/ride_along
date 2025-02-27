defmodule RideAlong.SqlPublisher do
  @moduledoc """
  Periodically runs SQL queries (via Tds) and sends the output to MQTT topics.
  """
  use GenServer

  alias EmqttFailover.Message
  alias RideAlong.MqttConnection

  require Logger

  @default_name __MODULE__
  def start_link(opts) do
    if opts[:start] do
      name = Keyword.get(opts, :name, @default_name)
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      :ignore
    end
  end

  defstruct [:tds, topic_prefix: "", results: %{}, connected?: false]

  @impl GenServer
  def init(_opts) do
    state = %__MODULE__{}
    RideAlong.PubSub.subscribe("mqtt", [:connected, :disconnected])
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

    state = %{
      state
      | tds: tds,
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
      {:ok, results, duration} ->
        Logger.info("#{__MODULE__} query success name=#{name} results=#{length(results)} duration=#{duration}")

        Logger.debug("#{__MODULE__} query result name=#{name} results=#{inspect(results)}")
        state = put_in(state.results[name], results)
        publish(state, name)
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("#{__MODULE__} query failed name=#{name} reason=#{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info({:connected, _connection}, state) do
    Logger.info("#{__MODULE__} connected")
    state = %{state | connected?: true}

    for name <- Map.keys(state.results) do
      publish(state, name)
    end

    {:noreply, state}
  end

  def handle_info({:disconnected, _connection, _reason}, state) do
    Logger.info("#{__MODULE__} disconnected")
    {:noreply, %{state | connected?: false}}
  end

  defp tds_query(tds, sql, parameters, retry_count \\ 0) do
    tds_parameters =
      for {name, value} <- parameters do
        %Tds.Parameter{
          name: "@#{name}",
          value: value
        }
      end

    try do
      {msec,
       %{
         columns: columns,
         rows: rows
       }} = :timer.tc(Tds, :query!, [tds, sql, tds_parameters], :millisecond)

      mapped =
        for row <- rows do
          columns
          |> Enum.zip(row)
          |> Map.new()
        end

      {:ok, mapped, msec}
    rescue
      e in Tds.Error ->
        if String.contains?(e.message, "Rerun the transaction.") and retry_count == 0 do
          Logger.info("#{__MODULE__} retrying due to deadlock query=#{inspect(sql)}")
          Process.sleep(500)
          tds_query(tds, sql, parameters, retry_count + 1)
        else
          {:error, e}
        end

      e in DBConnection.ConnectionError ->
        if retry_count < 6 do
          Logger.info("#{__MODULE__} retrying due to connection error query=#{inspect(sql)} reason=#{inspect(e)}")

          Process.sleep(500)
          tds_query(tds, sql, parameters, retry_count + 1)
        else
          {:error, e}
        end

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
              ROW_NUMBER() OVER (PARTITION BY ClientId, TripDate
                                 ORDER BY CASE WHEN PromiseTime = '00:00' THEN '50:00' ELSE PromiseTime END) AS ClientTripIndex
              FROM dbo.TRIP
             )
             SELECT t.Id AS Id, TripDate, RouteId,
             ClientId, c.UDF3 AS ClientNotificationPreference, ClientTripIndex,
             t.Status AS Status, Anchor, PickTime, PromiseTime,
             PickHouseNumber, PickAddress1, PickAddress2, PickCity, PickSt, PickZip,
             PickGridX, PickGridY,
             PickOrder, DropOrder, PerformPickup, PerformDropoff, t.LoadTime AS LoadTime, APtime1
             FROM Trips t
             JOIN dbo.CLIENT c ON t.ClientId = c.Id
             WHERE
               t.TripDate >= @service_date AND
               t.TripDate <= DATEADD(DAY,1,@service_date) AND
               PickGridX != 0 AND PickGridY != 0 AND
               ClientId > 0 AND
               (RouteId < 400000 OR RouteId >= 800000)],
        parameters: %{service_date: service_date},
        interval: 60_000
      },
      locations: %{
        sql: ~s[SELECT l.RouteId, VehicleId, Latitude, Longitude, Speed, Heading, l.LocationDate,
               (SELECT MAX(PickOrder) FROM dbo.TRIP t
                 WHERE t.RouteId = l.RouteId AND t.TripDate = @service_date AND t.PerformPickup != 0) AS LastPick,
               (SELECT MAX(DropOrder) FROM dbo.TRIP t
                 WHERE t.RouteId = l.RouteId AND t.TripDate = @service_date AND t.PerformDropoff != 0) AS LastDrop,
               (SELECT TOP 1 TripId FROM dbo.MDCVEHICLELOCATION
                 WHERE RouteId = l.RouteId AND LocationDate >= @service_date AND EventType='StopArrive'
                 ORDER BY LocationDate DESC) AS LastArrivedTrip,
               (SELECT TOP 1 t.Id FROM dbo.TRIP t
                 WHERE t.RouteId = l.RouteId AND t.TripDate = @service_date AND t.Status = 'S' AND APtime1 != '00:00'
                 ORDER BY t.APtime1 DESC) AS LastDispatchArrivedTrip
                  FROM dbo.MDCVEHICLELOCATION l
                  INNER JOIN (SELECT RouteId, MAX(LocationDate) AS LocationDate FROM dbo.MDCVEHICLELOCATION
                              WHERE LocationDate >= DATEADD(HOUR, 2, CAST(@service_date AS datetime))
                              GROUP BY RouteId) md
                              ON l.RouteId = md.RouteId AND l.LocationDate = md.LocationDate],
        parameters: %{service_date: service_date},
        interval: 5_000
      }
    }
  end

  defp publish(%{connected?: true} = state, name) do
    result = state.results[name]
    id = :erlang.unique_integer([:positive])

    payload =
      %{
        payload: result,
        id: id
      }
      |> :erlang.term_to_binary()
      |> :zlib.gzip()

    case :timer.tc(
           MqttConnection,
           :publish,
           [
             %Message{
               topic: state.topic_prefix <> Atom.to_string(name),
               payload: payload,
               qos: 1,
               retain?: true
             }
           ],
           :millisecond
         ) do
      {msec, :ok} ->
        Logger.info("#{__MODULE__} publish success name=#{name} id=#{id} size=#{byte_size(payload)} duration=#{msec}")

      {msec, {:error, reason}} ->
        Logger.warning("#{__MODULE__} publish failed name=#{name} id=#{id} reason=#{inspect(reason)} duration=#{msec}")
    end
  end

  defp publish(%{connected?: false}, name) do
    Logger.info("#{__MODULE__} not publishing because disconnected name=#{name}")

    :ok
  end
end
