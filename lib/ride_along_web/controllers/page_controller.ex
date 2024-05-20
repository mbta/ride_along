defmodule RideAlongWeb.PageController do
  use RideAlongWeb, :controller

  def home(conn, _params) do
    config = Application.get_env(:ride_along, __MODULE__)
    render(conn, :home, redirect_to: config[:redirect_to])
  end
end
