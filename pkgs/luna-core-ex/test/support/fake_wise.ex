defmodule LunaCore.FakeWise do
  @moduledoc "A fake Wise API. Each test starts its own. It keeps each call: {method, path}."
  @behaviour Plug
  import Plug.Conn

  def start do
    {:ok, state} = Agent.start_link(fn -> %{calls: [], status: "incoming_payment_waiting"} end)
    {:ok, server} = Bandit.start_link(plug: {__MODULE__, state}, ip: {127, 0, 0, 1}, port: 0, startup_log: false)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    %{state: state, url: "http://127.0.0.1:#{port}"}
  end

  def calls(%{state: s}), do: Agent.get(s, &Enum.reverse(&1.calls))
  def set_status(%{state: s}, status), do: Agent.update(s, &%{&1 | status: status})

  @impl true
  def init(state), do: state

  @impl true
  def call(conn, state) do
    {:ok, raw, conn} = read_body(conn)
    Agent.update(state, &%{&1 | calls: [{conn.method, conn.request_path} | &1.calls]})
    body = if raw == "", do: %{}, else: Jason.decode!(raw)

    case {conn.method, conn.path_info} do
      {"GET", ["v1", "profiles"]} -> json(conn, [%{"id" => 7, "type" => "PERSONAL"}])
      {"POST", ["v3", "profiles", _, "quotes"]} -> json(conn, %{"id" => "q-1"})
      {"POST", ["v1", "transfers"]} ->
        if body["targetAccount"] == 42 and body["quoteUuid"] == "q-1",
          do: json(conn, %{"id" => 555, "status" => "incoming_payment_waiting"}),
          else: send_resp(conn, 422, "bad transfer")
      {"GET", ["v1", "transfers", "555"]} -> json(conn, %{"id" => 555, "status" => Agent.get(state, & &1.status)})
      {"PUT", ["v1", "transfers", "555", "cancel"]} -> Agent.update(state, &%{&1 | status: "cancelled"}) && json(conn, %{"status" => "cancelled"})
      {"POST", ["v3", "profiles", _, "transfers", _, "payments"]} -> json(conn, %{"status" => "COMPLETED"})
      _ -> send_resp(conn, 404, "")
    end
  end

  defp json(conn, body), do: conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(body))
end
