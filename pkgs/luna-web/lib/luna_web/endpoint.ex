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
    # A camera frame is 5 MB or less, and base64 makes it 4/3 larger.
    websocket: [connect_info: [session: @session_options], max_frame_size: 8_000_000],
    longpoll: false

  plug Plug.RequestId
  plug Plug.Head
  plug Plug.Session, @session_options
  # The owner check comes before the static files, as in the Python app.
  plug LunaWeb.Owner

  # "no-cache": the browser keeps a file, but asks luna each time (the ETag
  # gives a short 304). Without it, a browser can use an old app.js after a deploy.
  plug Plug.Static, at: "/", from: :luna_web, only: ~w(app.js app.css mic-worklet.js fonts), cache_control_for_etags: "no-cache"
  plug Plug.Static, at: "/vendor", from: {:phoenix, "priv/static"}, only: ~w(phoenix.min.js), cache_control_for_etags: "no-cache"
  plug Plug.Static, at: "/vendor", from: {:phoenix_live_view, "priv/static"}, only: ~w(phoenix_live_view.min.js), cache_control_for_etags: "no-cache"

  plug LunaWeb.Router
end
