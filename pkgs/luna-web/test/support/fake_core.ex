defmodule LunaWeb.FakeCore do
  @moduledoc """
  A fake core API on a unix socket. It keeps each request that it gets.
  The replies follow the contract in "Build: the core API".
  """
  use Plug.Router

  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :keep
  plug :dispatch

  def start do
    path = Application.fetch_env!(:luna_web, :core_socket)
    File.rm(path)
    {:ok, _} = Agent.start_link(fn -> [] end, name: __MODULE__.Requests)
    {:ok, _} = Bandit.start_link(plug: __MODULE__, ip: {:local, path}, port: 0, startup_log: false)
    :ok
  end

  def reset, do: Agent.update(__MODULE__.Requests, fn _ -> [] end)
  def requests, do: Agent.get(__MODULE__.Requests, &Enum.reverse/1)

  defp keep(conn, _opts) do
    Agent.update(__MODULE__.Requests, &[{conn.method, conn.request_path, conn.body_params} | &1])
    conn
  end

  get "/api/history" do
    reply(conn, %{messages: [%{role: "user", text: "hello"}, %{role: "assistant", text: "hi"}]})
  end

  post "/api/chat" do
    reply(conn, %{reply: "reply: " <> conn.body_params["text"]})
  end

  get "/api/approvals" do
    reply(conn, %{approvals: [%{id: "a1b2c3", summary: "Test payment", created: "2026-11-20T00:00:00Z"}]})
  end

  post "/api/approvals/:id/approve" do
    reply(conn, %{result: "done"})
  end

  get "/api/money" do
    reply(conn, %{text: "Money is off. Refer to 'The gate for phase 2' in LUNA.org."})
  end

  get "/api/memory/graph" do
    reply(conn, %{
      nodes: [%{id: "a", title: "Polaris1", tags: ["project"], owner: "coops"}, %{id: "b", title: "Perth", tags: ["place"], owner: "luna"}],
      links: [%{source: "a", target: "b"}]
    })
  end

  get "/api/system" do
    reply(conn, %{
      started: "2026-11-20T00:00:00Z",
      update: "nixpkgs is less than 14 days old.",
      memory: "",
      settings: %{model: "claude-opus-5-5"},
      pending_approvals: 0,
      events: []
    })
  end

  defp reply(conn, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(body))
  end
end
