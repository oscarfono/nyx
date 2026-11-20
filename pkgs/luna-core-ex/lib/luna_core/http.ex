defmodule LunaCore.Http do
  @moduledoc """
  The outbound path of the core (blue team, B1). Each call to the internet
  (Anthropic, Wise, Telegram) goes through the filtering proxy on luna.
  systemd stops each direct connection: the unit allows localhost only.

  LUNA_HTTPS_PROXY is the proxy, for example http://127.0.0.1:8888.
  Without it (the tests), the calls go direct.
  """

  @doc "The Req options for a call to the internet."
  def options(env \\ System.get_env()) do
    case Map.get(env, "LUNA_HTTPS_PROXY") do
      value when value in [nil, ""] ->
        []

      url ->
        uri = URI.parse(url)
        [connect_options: [proxy: {String.to_existing_atom(uri.scheme), uri.host, uri.port, []}]]
    end
  end
end
