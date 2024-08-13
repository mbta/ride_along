defmodule RideAlong.RiderNotifierTest do
  @moduledoc false
  use ExUnit.Case

  alias RideAlong.Adept
  alias RideAlong.AdeptFixtures

  setup do
    {:ok, _} = RideAlong.RiderNotifier.start_link(start: true, name: __MODULE__)
    RideAlong.PubSub.subscribe("notification:trip")

    on_exit(fn ->
      Adept.set_vehicles([])
      Adept.set_trips([])
    end)

    :ok
  end

  test "triggers a notification when the trip is the next pickup" do
    trip_id = :erlang.unique_integer()

    Adept.set_vehicles([AdeptFixtures.vehicle_fixture()])
    Adept.set_trips([AdeptFixtures.trip_fixture(%{trip_id: trip_id})])

    assert_receive {:trip_notification, %Adept.Trip{trip_id: ^trip_id}}
  end

  test "triggers a notification when the trip is promised in the next 30m" do
    trip_id = :erlang.unique_integer()

    Adept.set_trips([
      AdeptFixtures.trip_fixture(%{trip_id: trip_id, promise_time: DateTime.utc_now()})
    ])

    assert_receive {:trip_notification, %Adept.Trip{trip_id: ^trip_id}}
  end

  test "does not trigger a notification when the pickup is not next and the promise time is further in the future" do
    trip_id = :erlang.unique_integer()

    Adept.set_trips([AdeptFixtures.trip_fixture(%{trip_id: trip_id})])

    refute_receive {:trip_notification, %Adept.Trip{trip_id: ^trip_id}}
  end

  test "does not re-trigger a notification" do
    trip_id = :erlang.unique_integer()

    Adept.set_vehicles([AdeptFixtures.vehicle_fixture()])
    Adept.set_trips([AdeptFixtures.trip_fixture(%{trip_id: trip_id})])

    assert_receive {:trip_notification, _}

    Adept.set_vehicles([AdeptFixtures.vehicle_fixture()])

    refute_receive {:trip_notification, %Adept.Trip{trip_id: ^trip_id}}
  end
end
