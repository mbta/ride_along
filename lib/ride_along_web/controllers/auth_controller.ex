defmodule RideAlongWeb.AuthController do
  use RideAlongWeb, :controller
  require Logger
  alias RideAlongWeb.AuthManager

  plug Ueberauth

  def logout(conn, _) do
    AuthManager.logout(conn)
  end

  def request(conn, _params) do
    conn
    |> redirect(to: "/not-found")
    |> halt()
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _) do
    redirect =
      if redirect_to = get_session(conn, :redirect_to) do
        [external: redirect_to]
      else
        [to: ~p"/"]
      end

    conn = delete_session(conn, :redirect_to)

    conn
    |> AuthManager.login(auth)
    |> redirect(redirect)
  end

  def callback(conn, _) do
    reason = Map.get(conn.assigns, :ueberauth_failure)

    Logger.info("{__MODULE__} login failure reason=#{inspect(reason)}")

    conn
    |> send_resp(:unauthorized, "unauthorized")
    |> halt()
  end
end
