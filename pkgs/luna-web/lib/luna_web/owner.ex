defmodule LunaWeb.Owner do
  @moduledoc """
  Accepts a request only from the owner login.

  tailscale serve adds the header Tailscale-User-Login to each request from
  a tailnet user. The endpoint listens on 127.0.0.1 only, so a request from
  outside luna cannot set the header.

  The LiveView socket does not go through this plug. The plug writes the
  login in the signed session, and on_mount/4 compares the session login
  with the owner login.
  """
  import Plug.Conn

  @header "tailscale-user-login"
  @session_key "owner_login"

  def init(opts), do: opts

  def call(conn, _opts) do
    owner = owner_login()

    case get_req_header(conn, @header) do
      [^owner] ->
        conn
        |> fetch_session()
        |> put_session(@session_key, owner)
        |> assign(:owner_login, owner)

      _ ->
        LunaWeb.Audit.write("web.refused", %{"reason" => "login", "path" => conn.request_path})

        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(403, "LUNA: this page is for the owner only.")
        |> halt()
    end
  end

  def on_mount(:owner, _params, session, socket) do
    owner = owner_login()

    case session do
      %{@session_key => ^owner} ->
        {:cont, Phoenix.Component.assign(socket, :owner_login, owner)}

      _ ->
        LunaWeb.Audit.write("web.refused", %{"reason" => "session", "path" => "/live"})
        {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    end
  end

  @doc "True when the signed session has the owner login."
  def owner_session?(session), do: Map.get(session, @session_key) == owner_login()

  # An empty owner login would accept an empty header. Refuse to start.
  defp owner_login do
    case Application.fetch_env!(:luna_web, :owner_login) do
      login when is_binary(login) and login != "" -> login
      _ -> raise "LUNA: the owner login is empty."
    end
  end
end
