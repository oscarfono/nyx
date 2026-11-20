defmodule LunaCore.FakeHomeserver do
  @moduledoc """
  A fake Synapse. Each test starts its own. The test gives the sync bodies in
  order. After the last body, a sync waits 50 ms and returns no events.
  The fake keeps each request: {method, path, body}.
  """
  @behaviour Plug
  import Plug.Conn

  def start(syncs, opts \\ []) do
    {:ok, state} = Agent.start_link(fn -> %{syncs: syncs, requests: [], login_status: Keyword.get(opts, :login_status, 200)} end)
    {:ok, server} = Bandit.start_link(plug: {__MODULE__, state}, ip: {127, 0, 0, 1}, port: 0, startup_log: false)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    %{state: state, url: "http://127.0.0.1:#{port}"}
  end

  def add_sync(%{state: state}, body), do: Agent.update(state, &%{&1 | syncs: &1.syncs ++ [body]})
  def requests(%{state: state}), do: Agent.get(state, &Enum.reverse(&1.requests))

  @doc "Waits up to 3 s for a request that matches the function."
  def await(fake, fun, tries \\ 60) do
    case Enum.find(requests(fake), fun) do
      nil when tries > 0 -> Process.sleep(50) && await(fake, fun, tries - 1)
      found -> found
    end
  end

  @impl true
  def init(state), do: state

  @impl true
  def call(conn, state) do
    {:ok, raw, conn} = read_body(conn)
    body = if raw == "", do: nil, else: Jason.decode!(raw)
    Agent.update(state, &%{&1 | requests: [{conn.method, conn.request_path, body} | &1.requests]})
    reply(conn, conn.method, conn.path_info, state)
  end

  defp reply(conn, "POST", ["_matrix", "client", "v3", "login"], state) do
    case Agent.get(state, & &1.login_status) do
      200 -> json(conn, 200, %{"user_id" => "@luna:test", "device_id" => "D1", "access_token" => "token-1"})
      status -> json(conn, status, %{"errcode" => "M_FORBIDDEN"})
    end
  end

  defp reply(conn, "GET", ["_matrix", "client", "v3", "sync"], state) do
    case Agent.get_and_update(state, fn s -> {List.first(s.syncs), %{s | syncs: Enum.drop(s.syncs, 1)}} end) do
      nil ->
        Process.sleep(50)
        json(conn, 200, %{"next_batch" => "idle"})

      {:status, status} ->
        json(conn, status, %{"errcode" => "M_UNKNOWN_TOKEN"})

      body ->
        json(conn, 200, body)
    end
  end

  defp reply(conn, "POST", ["_matrix", "client", "v3", "createRoom"], _),
    do: json(conn, 200, %{"room_id" => "!owner:test"})

  defp reply(conn, _method, _path, _state), do: json(conn, 200, %{"event_id" => "$e"})

  defp json(conn, status, body),
    do: conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
end
