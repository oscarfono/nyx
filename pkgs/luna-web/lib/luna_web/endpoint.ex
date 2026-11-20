defmodule LunaWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :luna_web

  # tailscale serve gives HTTPS to the browser, so the cookie can be secure.
  @session_options [
    store: :cookie,
    key: "_luna_web",
    signing_salt: "luna-session",
    same_site: "Strict",
    secure: true,
    http_only: true
  ]

  # Phoenix dispatches the socket before the plugs below.
  # LunaWeb.Owner.on_mount/4 checks the owner. check_origin checks the origin.
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false

  plug Plug.RequestId
  plug Plug.Head
  plug Plug.Session, @session_options
  # The owner check comes before the static files, as in the Python app.
  plug LunaWeb.Owner

  plug Plug.Static, at: "/", from: :luna_web, only: ~w(app.js app.css)
  plug Plug.Static, at: "/vendor", from: {:phoenix, "priv/static"}, only: ~w(phoenix.min.js)
  plug Plug.Static, at: "/vendor", from: {:phoenix_live_view, "priv/static"}, only: ~w(phoenix_live_view.min.js)

  plug LunaWeb.Router
end
