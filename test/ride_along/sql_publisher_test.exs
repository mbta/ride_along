defmodule RideAlong.SqlPublisherTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias RideAlong.SqlPublisher

  describe "start_link/1" do
    test "is ignored if start is not true" do
      assert :ignore = SqlPublisher.start_link(name: __MODULE__)
    end

    test "starts if provided start: true" do
      assert {:ok, _pid} = SqlPublisher.start_link(start: true, name: __MODULE__)
    end
  end

  describe "handle_continue(:start_timers)" do
    test "sends an initial message for each query" do
      state = %SqlPublisher{}

      assert {:noreply, new_state, {:continue, :connect}} =
               SqlPublisher.handle_continue(:start_timers, state)

      assert_received {:query, :trips}
      assert_received {:query, :locations}
      assert %{trips: [], locations: []} = new_state.results
    end
  end
end
