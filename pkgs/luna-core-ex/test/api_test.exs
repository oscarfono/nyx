defmodule LunaCore.ApiTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias LunaCore.{Api, Approvals}

  @moduletag :tmp_dir

  defmodule FakeAgent do
    @moduledoc false
    def ask(test, text, images) do
      send(test, {:asked, text, images})
      "reply: " <> text
    end

    def transcript(_), do: [%{role: "user", text: "hello"}, %{role: "assistant", text: "hi"}]
  end

  setup %{tmp_dir: tmp} do
    dir = Path.join(tmp, "approvals")
    File.mkdir_p!(dir)
    audit = Path.join(tmp, "audit.jsonl")
    File.write!(audit, "")
    {:ok, approvals} = Approvals.start_link(dir: dir, audit: audit, name: nil)
    test = self()
    :ok = Approvals.register(approvals, "test", fn params -> send(test, {:ran, params}) && "done" end)

    core = [agent: {FakeAgent, self()}, approvals: approvals, audit: audit, started: DateTime.utc_now()]
    %{core: core, approvals: approvals, tmp: tmp}
  end

  defp call(core, method, path, body \\ nil) do
    conn = if body, do: conn(method, path, Jason.encode!(body)) |> put_req_header("content-type", "application/json"), else: conn(method, path)
    conn = Api.call(conn, Api.init(core))
    {conn.status, Jason.decode!(conn.resp_body)}
  end

  test "history", %{core: core} do
    {200, body} = call(core, :get, "/api/history")
    assert Enum.at(body["messages"], 1) == %{"role" => "assistant", "text" => "hi"}
  end

  test "chat with an image", %{core: core} do
    data = Base.encode64(<<0xFF, 0xD8>> <> "fake-jpeg")
    image = %{"media_type" => "image/jpeg", "data" => data}
    assert {200, %{"reply" => "reply: what is this?"}} = call(core, :post, "/api/chat", %{text: "what is this?", image: image})
    assert_received {:asked, "what is this?", [{"image/jpeg", ^data}]}
  end

  test "a voice message is marked", %{core: core} do
    assert {200, _} = call(core, :post, "/api/chat", %{text: "next swing?", channel: "voice"})
    assert_received {:asked, "[voice] next swing?", []}
  end

  test "a bad image is refused", %{core: core} do
    assert {400, _} = call(core, :post, "/api/chat", %{text: "x", image: %{media_type: "image/gif", data: "AA=="}})
    assert {400, _} = call(core, :post, "/api/chat", %{text: "x", image: %{media_type: "image/png", data: "not base64!"}})
    assert {400, %{"error" => "Write a message."}} = call(core, :post, "/api/chat", %{text: "  "})
    refute_received {:asked, _, _}
  end

  test "approve", %{core: core, approvals: approvals} do
    {:ok, item} = Approvals.request(approvals, "test", %{"x" => 1}, "Test payment")
    {200, listed} = call(core, :get, "/api/approvals")
    assert hd(listed["approvals"])["summary"] == "Test payment"
    assert {200, %{"result" => "done"}} = call(core, :post, "/api/approvals/#{item.id}/approve", %{})
    assert_received {:ran, %{"x" => 1}}
  end

  test "an unknown action is refused", %{core: core} do
    assert {400, _} = call(core, :post, "/api/approvals/abc/delete", %{})
  end

  test "money is off by default", %{core: core} do
    {200, body} = call(core, :get, "/api/money")
    assert body["text"] =~ "Money is off"
  end

  test "system", %{core: core} do
    {200, data} = call(core, :get, "/api/system")
    assert data["pending_approvals"] == 0 and Map.has_key?(data, "update")
  end

  test "serve on a unix socket", %{core: core} do
    # A unix socket path has 107 bytes or less, so the path of tmp_dir is too long.
    path = Path.join(System.tmp_dir!(), "luna-api-#{System.unique_integer([:positive])}.sock")
    on_exit(fn -> File.rm(path) end)
    File.write!(path, "an old socket")
    start_supervised!({Api, socket: path, core: core})
    {:ok, %{status: 200, body: body}} = Req.get("http://core/api/money", unix_socket: path, retry: false)
    assert body["text"] =~ "Money is off"
    assert {:ok, %File.Stat{type: :other}} = File.lstat(path)
  end
end
