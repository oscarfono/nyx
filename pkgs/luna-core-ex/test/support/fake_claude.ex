defmodule LunaCore.FakeClaude do
  @moduledoc """
  A fake Messages API. Each test starts its own. The test gives a list of
  replies: {status, body}. The fake keeps each request body and its headers.
  """
  @behaviour Plug
  import Plug.Conn

  def start(replies) do
    {:ok, state} = Agent.start_link(fn -> %{replies: replies, requests: []} end)
    {:ok, server} = Bandit.start_link(plug: {__MODULE__, state}, ip: {127, 0, 0, 1}, port: 0, startup_log: false)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    %{state: state, base_url: "http://127.0.0.1:#{port}"}
  end

  def requests(%{state: state}), do: Agent.get(state, &Enum.reverse(&1.requests))

  @impl true
  def init(state), do: state

  @impl true
  def call(%{method: "POST", request_path: "/v1/messages"} = conn, state) do
    {:ok, raw, conn} = read_body(conn, length: 20_000_000)
    headers = Map.new(conn.req_headers)

    {status, body} =
      Agent.get_and_update(state, fn s ->
        {reply, rest} =
          case s.replies do
            [] -> {{500, %{"error" => %{"message" => "no reply left"}}}, []}
            [reply | rest] -> {reply, rest}
          end

        {reply, %{s | replies: rest, requests: [%{body: Jason.decode!(raw), headers: headers} | s.requests]}}
      end)

    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
  end

  def call(conn, _state), do: send_resp(conn, 404, "")

  @doc "A message from the API."
  def message(stop_reason, content), do: %{"model" => "claude-opus-5-5", "stop_reason" => stop_reason, "content" => content, "usage" => %{"input_tokens" => 10, "output_tokens" => 5}}
  def text(t), do: %{"type" => "text", "text" => t}
  def tool_use(id, name, input), do: %{"type" => "tool_use", "id" => id, "name" => name, "input" => input}
end
