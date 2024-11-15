defmodule RideAlong.EtaMonitorTest do
  @moduledoc false
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias RideAlong.Adept
  alias RideAlong.AdeptFixtures
  alias RideAlong.EtaMonitor
  alias RideAlong.OpenRouteServiceFixtures, as: ORSFixtures

  describe "update_trips/2" do
    setup do
      today = ~D[2024-06-06]
      now = ~U[2024-06-06T13:47:00Z]
      route_id = 2345

      Adept.set_vehicles([
        AdeptFixtures.vehicle_fixture(%{
          route_id: route_id,
          vehicle_id: "2345",
          last_pick: 5,
          last_drop: 6,
          timestamp: now
        })
      ])

      on_exit(fn ->
        Adept.set_vehicles([])
      end)

      state = %EtaMonitor{}

      {:ok, route_id: route_id, today: today, now: now, state: state}
    end

    test "logs a message when the trip status changes", %{
      route_id: route_id,
      today: today,
      now: now,
      state: state
    } do
      pick_time = ~U[2024-06-06T14:00:00Z]

      trip =
        AdeptFixtures.trip_fixture(%{
          trip_id: 1,
          route_id: route_id,
          date: today,
          pick_time: pick_time,
          promise_time: pick_time,
          pick_order: 7,
          drop_order: 9,
          pickup_performed?: false
        })

      stub_ors!()

      state = EtaMonitor.update_trips(state, [trip], now)

      log_level!(:info)

      log =
        capture_log(fn ->
          EtaMonitor.update_trips(state, [%{trip | pickup_performed?: true}], now)
        end)

      assert log =~ "EtaMonitor"

      log =
        capture_log(fn ->
          EtaMonitor.update_trips(state, [%{trip | dropoff_performed?: true}], now)
        end)

      refute log =~ "EtaMonitor"
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

  def stub_ors! do
    ORSFixtures.stub(ORSFixtures.fixture())
  end

  def log_level!(level) do
    old_level = Logger.level()
    Logger.configure(level: level)

    on_exit(fn ->
      Logger.configure(level: old_level)
    end)
  end
end
