defmodule RideAlongWeb.Api do
  @moduledoc """
  Plug for validating incoming API requests.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init([]), do: []

  @impl Plug
  def call(conn, _params) do
    with [header] <- get_req_header(conn, "authorization"),
         "bearer " <> _ <- String.downcase(header),
         [_, token] <- String.split(header, " ", parts: 2),
         true <- valid_api_key?(token) do
      conn
    else
      _ ->
        unauthorized(conn)
    end
  end

  def valid_api_key?(token) do
    api_keys = Application.get_env(:ride_along, __MODULE__)[:api_keys]

    Map.has_key?(api_keys, String.trim(token))
  end

  def unauthorized(conn) do
    conn
    |> JSONAPI.ErrorView.send_error(:unauthorized, %{status: 401, code: "UNAUTHORIZED"})
    |> halt()
  end
end
