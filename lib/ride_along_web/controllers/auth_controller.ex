defmodule RideAlongWeb.AuthController do
  use RideAlongWeb, :controller
  alias RideAlongWeb.AuthManager

  plug Ueberauth

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
    conn
    |> send_resp(:unauthorized, "unauthorized")
    |> halt()
  end
end
