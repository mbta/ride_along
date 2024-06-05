defmodule RideAlongWeb.AuthManager do
  @moduledoc """
  Helper functions for authentication (login/logout/verification).
  """
  # this isn't really a controller, but it gives us some functions we want to use
  use RideAlongWeb, :controller

  def init(opts), do: opts

  def call(conn, opts) do
    required_roles = Keyword.get(opts, :roles, [])

    if authenticated?(conn) and Enum.all?(required_roles, &has_role?(conn, &1)) do
      conn
    else
      conn
      |> put_session(:redirect_to, request_url(conn))
      |> redirect(to: ~p[/auth/keycloak])
    end
  end

  def login(conn, auth) do
    logout_url = UeberauthOidcc.initiate_logout_url(auth)

    roles = auth.extra.raw_info.userinfo["roles"] || []

    conn
    |> put_session(:logout_url, logout_url)
    |> put_session(:roles, roles)
    |> put_session(:expires_at, System.system_time(:second) + 1_800)
  end

  def logout(conn) do
    redirect =
      if logout_url = get_session(conn, :logout_url) do
        [external: logout_url]
      else
        [to: ~p"/"]
      end

    conn
    |> clear_session()
    |> configure_session(drop: true)
    |> redirect(redirect)
    |> halt()
  end

  def authenticated?(conn) do
    get_session(conn, :logout_url) != nil and
      get_session(conn, :expires_at) > System.system_time(:second)
  end

  def has_role?(conn, role) do
    roles = get_session(conn, :roles, [])
    role in roles
  end
end
