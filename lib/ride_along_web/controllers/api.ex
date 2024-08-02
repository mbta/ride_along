defmodule RideAlongWeb.Api do
  @moduledoc """
  Plug for validating incoming API requests.
  """
  import Plug.Conn
  @behaviour Plug

  @impl Plug
  def init([]), do: []

  @impl Plug
  def call(conn, _params) do
    case Enum.map(get_req_header(conn, "authorization"), &String.downcase/1) do
      ["bearer " <> token] ->
        if valid_api_key?(token) do
          conn
        else
          unauthorized(conn)
        end

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
