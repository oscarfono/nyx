defmodule LunaWeb.Router do
  use Phoenix.Router
  import Plug.Conn
  import Phoenix.Controller
  import Phoenix.LiveView.Router

  # The same policy as the Python app. The page loads scripts from the app only.
  @csp "default-src 'none'; script-src 'self'; style-src 'self'; font-src 'self'; img-src 'self' data: blob:; " <>
         "media-src 'self' blob:; connect-src 'self'; base-uri 'none'; form-action 'none'; " <>
         "frame-ancestors 'none'"

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {LunaWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" => @csp,
      "referrer-policy" => "no-referrer",
      "cache-control" => "no-store"
    }
  end

  scope "/", LunaWeb do
    pipe_through :browser

    live_session :owner, on_mount: {LunaWeb.Owner, :owner} do
      live "/", HomeLive
    end
  end
end
