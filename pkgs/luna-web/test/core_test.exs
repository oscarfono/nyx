defmodule LunaWeb.CoreTest do
  # One fake core serves all tests, so these tests do not run at the same time.
  use LunaWeb.Case, async: false

  alias LunaWeb.{Core, FakeCore}

  @owner "owner@example.com"

  setup do
    FakeCore.reset()
  end

  @tag :capture_log
  test "a socket from another origin gets 403, and the core gets no request" do
    conn =
      build_conn()
      |> put_req_header("origin", "https://evil.example")
      |> get("/live/websocket", %{"vsn" => "2.0.0"})

    assert conn.status == 403
    assert FakeCore.requests() == []
  end

  test "chat with an image" do
    data = Base.encode64(<<0xFF, 0xD8>> <> "fake-jpeg")
    image = %{"media_type" => "image/jpeg", "data" => data}
    assert Core.chat("what is this?", image) == {:ok, "reply: what is this?"}

    assert [{"POST", "/api/chat", %{"text" => "what is this?", "image" => ^image}}] =
             FakeCore.requests()
  end

  test "a bad image is refused, and the core gets no request" do
    assert {:error, _} = Core.chat("x", %{"media_type" => "image/gif", "data" => "AA=="})
    assert {:error, _} = Core.chat("x", %{"media_type" => "image/png", "data" => "not base64!"})
    assert {:error, "Write a message."} = Core.chat("  ", nil)
    assert FakeCore.requests() == []
  end

  test "approve from the page" do
    assert {:ok, [%{"summary" => "Test payment", "id" => id}]} = Core.approvals()
    assert Core.decide(id, "approve") == {:ok, "done"}
    assert {"POST", "/api/approvals/a1b2c3/approve", %{}} in FakeCore.requests()
  end

  test "a bad approval ID or action is refused, and the core gets no request" do
    assert {:error, _} = Core.decide("../money", "approve")
    assert {:error, _} = Core.decide("a1b2c3", "delete")
    assert FakeCore.requests() == []
  end

  test "money is off by default" do
    assert {:ok, text} = Core.money()
    assert text =~ "Money is off"
  end

  test "the system panel" do
    assert {:ok, %{"pending_approvals" => 0, "update" => _}} = Core.system()
  end

  test "the page has the four panels" do
    conn = build_conn() |> put_req_header("tailscale-user-login", @owner) |> get("/")
    body = html_response(conn, 200)

    for label <- ["Chat", "Approvals", "Money", "System"], do: assert(body =~ label)

    assert body =~ ~s(phx-hook="Camera")
  end
end
