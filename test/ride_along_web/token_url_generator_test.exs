defmodule RideAlongWeb.TokenUrlGeneratorTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias RideAlong.Adept
  alias RideAlong.AdeptFixtures
  alias RideAlongWeb.TokenUrlGenerator

  describe "generate/1" do
    setup do
      on_exit(fn ->
        Adept.set_trips([])
      end)
    end

    test "returns {:ok, url} for a valid trip" do
      trip = AdeptFixtures.trip_fixture()
      Adept.set_trips([trip])

      assert {:ok, "https://" <> _} = TokenUrlGenerator.generate(trip.trip_id)
    end

    test "returns :error for an invalid trip ID" do
      assert :error = TokenUrlGenerator.generate(0)
    end
  end
end
