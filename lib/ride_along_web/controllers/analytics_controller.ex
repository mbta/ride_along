defmodule RideAlongWeb.AnalyticsController do
  use RideAlongWeb, :controller

  plug :fetch_session

  def create(conn, _params) do
    Logger.metadata(uid: get_session(conn, :uid))

    conn =
      with {:ok, body, conn} <- read_body(conn),
           {:ok, decoded} <- Jason.decode(body) do
        user_agent =
          case get_req_header(conn, "user-agent") do
            [user_agent | _] -> inspect(user_agent)
            _ -> nil
          end

        {level, params} = log_decoded(decoded)
        log = [module: __MODULE__, user_agent: user_agent] ++ params

        Logster.log(level, log)

        conn
      else
        _ -> conn
      end

    conn
    |> send_resp(:created, "")
    |> halt()
  end

  defp log_decoded(%{"name" => metric, "value" => value, "path" => path}) do
    {:info, [metric: metric, value: value, path: path]}
  end

  defp log_decoded(%{
         "name" => error,
         "message" => message,
         "source" => source,
         "lineno" => lineno,
         "colno" => colno,
         "path" => path
       }) do
    {:error,
     [
       error: inspect(error),
       message: inspect(message),
       source: source,
       lineno: lineno,
       colno: colno,
       path: path
     ]}
  end

  defp log_decoded(decoded) do
    {:warning, [decoded: Jason.encode!(decoded)]}
  end
end
