defmodule RideAlongWeb.TokenUrlGenerator do
  @moduledoc """
  Generates the full token URL for a given trip ID.
  """
  use RideAlongWeb, :html

  def generate(trip_id) do
    if token = RideAlong.LinkShortener.get_token(trip_id) do
      {:ok, url(~p"/t/#{token}")}
    else
      :error
    end
  end
end
