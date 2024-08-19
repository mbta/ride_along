defmodule RideAlongWeb.AnalyticsController do
  use RideAlongWeb, :controller
  require Logger

  def create(conn, _params) do
    conn =
      with {:ok, body, conn} <- read_body(conn),
           {:ok, %{"path" => path, "name" => name, "value" => value}} <- Jason.decode(body),
           [user_agent | _] <- get_req_header(conn, "user-agent") do
        Logger.info(
          "#{__MODULE__} metric path=#{path} name=#{name} value=#{value} user_agent=#{inspect(user_agent)}"
        )

        conn
      else
        _ -> conn
      end

    conn
    |> send_resp(:created, "")
    |> halt()
  end
end
