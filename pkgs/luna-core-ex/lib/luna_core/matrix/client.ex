defmodule LunaCore.Matrix.Client do
  @moduledoc """
  The Matrix client-server API calls that the bot uses. Each function returns
  {:ok, body} or {:error, status_or_reason}. The homeserver is Synapse on
  127.0.0.1, so the bot sends no request off the host.
  """

  def login(homeserver, user, password) do
    post(homeserver, nil, "/_matrix/client/v3/login", %{
      "type" => "m.login.password",
      "identifier" => %{"type" => "m.id.user", "user" => user},
      "password" => password,
      "initial_device_display_name" => "luna-core"
    })
  end

  def sync(homeserver, token, since, timeout_ms) do
    params = [timeout: timeout_ms, full_state: "false"] ++ if(since, do: [since: since], else: [])

    request(homeserver, token, :get, "/_matrix/client/v3/sync",
      params: params,
      receive_timeout: timeout_ms + 30_000
    )
  end

  def send_message(homeserver, token, room, content) do
    txn = "luna-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}"
    put(homeserver, token, "/_matrix/client/v3/rooms/#{enc(room)}/send/m.room.message/#{txn}", content)
  end

  def typing(homeserver, token, room, user, on?) do
    body = if on?, do: %{"typing" => true, "timeout" => 120_000}, else: %{"typing" => false}
    put(homeserver, token, "/_matrix/client/v3/rooms/#{enc(room)}/typing/#{enc(user)}", body)
  end

  def join(homeserver, token, room), do: post(homeserver, token, "/_matrix/client/v3/join/#{enc(room)}", %{})

  def create_room(homeserver, token, body), do: post(homeserver, token, "/_matrix/client/v3/createRoom", body)

  defp post(hs, token, path, body), do: request(hs, token, :post, path, json: body)
  defp put(hs, token, path, body), do: request(hs, token, :put, path, json: body)

  defp request(homeserver, token, method, path, opts) do
    headers = if token, do: [{"authorization", "Bearer " <> token}], else: []

    case Req.request([method: method, url: homeserver <> path, headers: headers, retry: false] ++ opts) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, status}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end

  defp enc(segment), do: URI.encode(segment, &URI.char_unreserved?/1)
end
