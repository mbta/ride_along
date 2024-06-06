defmodule RideAlong.EtaMonitorTest do
  @moduledoc false
  use ExUnit.Case
  import ExUnit.CaptureLog

  alias RideAlong.Adept
  alias RideAlong.EtaMonitor

  describe "update_trips/2" do
    setup do
      route_id = 2345

      Adept.set_vehicles([
        %Adept.Vehicle{route_id: route_id, vehicle_id: "2345", last_pick: 5, last_drop: 6}
      ])

      state = %EtaMonitor{}

      {:ok, route_id: route_id, state: state}
    end

    test "logs a message when the trip status changes", %{route_id: route_id, state: state} do
      today = ~D[2024-06-06]
      now = ~U[2024-06-06T13:47:00Z]
      pick_time = ~U[2024-06-06T14:00:00Z]

      trip = %Adept.Trip{
        trip_id: 1,
        route_id: route_id,
        date: today,
        pick_time: pick_time,
        promise_time: pick_time,
        pick_order: 5,
        drop_order: 9,
        pickup_performed?: true
      }

      state = EtaMonitor.update_trips(state, [trip], now)

      log_level!(:info)

      log =
        capture_log(fn ->
          EtaMonitor.update_trips(state, [trip], now)
        end)

      refute log =~ "EtaMonitor"

      log =
        capture_log(fn ->
          EtaMonitor.update_trips(state, [%{trip | drop_order: 6, dropoff_performed?: true}], now)
        end)

      assert log =~ "EtaMonitor"
    end
  end

  describe "clean_state/2" do
    test "removes items which are more than a day in the past" do
      tomorrow = ~D[2024-06-07]
      today = ~D[2024-06-06]
      yesterday = ~D[2024-06-05]
      day_before_yesterday = ~D[2024-06-04]

      state = %EtaMonitor{
        trip_date_to_key: %{
          {1, tomorrow} => {},
          {2, today} => {},
          {3, yesterday} => {},
          {4, day_before_yesterday} => {}
        }
      }

      state = EtaMonitor.clean_state(state, today)

      assert Enum.sort(Map.keys(state.trip_date_to_key)) == [
               {1, tomorrow},
               {2, today},
               {3, yesterday}
             ]
    end
  end

  def log_level!(level) do
    old_level = Logger.level()
    Logger.configure(level: level)

    on_exit(fn ->
      Logger.configure(level: old_level)
    end)
  end
end
