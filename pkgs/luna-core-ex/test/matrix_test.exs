defmodule LunaCore.MatrixTest do
  use ExUnit.Case, async: true

  alias LunaCore.{Approvals, FakeHomeserver}
  alias LunaCore.Matrix.Bot

  @moduletag :tmp_dir
  @owner "@coops:test"

  defmodule FakeAgent do
    @moduledoc false
    def ask(test, text, _images) do
      send(test, {:asked, text})
      "**Reply** to #{text}"
    end

    def reset(test), do: send(test, :reset)
  end

  setup %{tmp_dir: tmp} do
    dir = Path.join(tmp, "approvals")
    File.mkdir_p!(dir)
    audit = Path.join(tmp, "audit.jsonl")
    {:ok, approvals} = Approvals.start_link(dir: dir, audit: audit, name: nil)
    test = self()
    :ok = Approvals.register(approvals, "test", fn _ -> send(test, :ran) && "done" end)
    %{tmp: tmp, audit: audit, approvals: approvals}
  end

  defp start_bot(ctx, syncs, opts \\ []) do
    fake = FakeHomeserver.start(syncs, opts)
    test = self()

    {:ok, bot} =
      Bot.start_link(
        homeserver: fake.url, user: "@luna:test", owner: @owner, password: "pw",
        state_dir: ctx.tmp, audit: ctx.audit, agent: {FakeAgent, test}, approvals: ctx.approvals,
        nudge: fn text -> send(test, {:nudge, text}) end, sync_timeout: 0, name: nil
      )

    {bot, fake}
  end

  defp now, do: System.system_time(:millisecond) + 1_000

  defp message(room, sender, body, ts \\ nil) do
    %{"next_batch" => "b#{System.unique_integer([:positive])}",
      "rooms" => %{"join" => %{room => %{"timeline" => %{"events" => [
        %{"type" => "m.room.message", "sender" => sender, "origin_server_ts" => ts || now(),
          "content" => %{"msgtype" => "m.text", "body" => body}}]}}}}}
  end

  defp sent(fake, room) do
    FakeHomeserver.await(fake, fn {m, p, _} -> m == "PUT" and String.contains?(p, "/rooms/#{URI.encode_www_form(room)}/send/") end)
  end

  test "route sends the commands to code and the rest to the agent" do
    assert Bot.route("approve a1b2c3") == {:approve, "a1b2c3"}
    assert Bot.route("Deny a1b2c3") == {:deny, "a1b2c3"}
    assert Bot.route("pending") == :pending
    assert Bot.route("/new") == :new
    assert Bot.route("approve the plan for March") == {:ask, "approve the plan for March"}
    assert Bot.route("  what is safe to spend?  ") == {:ask, "what is safe to spend?"}
  end

  test "the content has Markdown as HTML" do
    content = Bot.content("**hi**")
    assert content["body"] == "**hi**"
    assert content["formatted_body"] =~ "<strong>hi</strong>"
  end

  test "login, the first sync, and the owner room", ctx do
    {_bot, fake} = start_bot(ctx, [%{"next_batch" => "s1"}])
    assert {"POST", "/_matrix/client/v3/createRoom", body} = FakeHomeserver.await(fake, fn {_, p, _} -> p =~ "createRoom" end)
    assert body["invite"] == [@owner] and body["room_version"] == "11"
    assert File.read!(Path.join(ctx.tmp, "owner-room")) == "!owner:test"
    assert File.read!(Path.join(ctx.tmp, "matrix-session.json")) =~ "token-1"
    assert {:ok, %{mode: mode}} = File.stat(Path.join(ctx.tmp, "matrix-session.json"))
    assert Bitwise.band(mode, 0o077) == 0
  end

  test "an owner message goes to the agent, and the reply comes back as HTML", ctx do
    {_bot, fake} = start_bot(ctx, [%{"next_batch" => "s1"}, message("!owner:test", @owner, "next swing?")])
    assert_receive {:asked, "next swing?"}, 3_000
    {"PUT", _, body} = sent(fake, "!owner:test")
    assert body["formatted_body"] =~ "<strong>Reply</strong>"
  end

  test "a message from another user, or from before the start, does not go to the agent", ctx do
    {_bot, _fake} =
      start_bot(ctx, [
        %{"next_batch" => "s1"},
        message("!owner:test", "@stranger:test", "hello"),
        message("!owner:test", @owner, "old", 1)
      ])

    refute_receive {:asked, _}, 500
    assert File.read!(ctx.audit) =~ "matrix.message_ignored"
  end

  test "approve in Matrix runs the executor in code", ctx do
    {:ok, item} = Approvals.request(ctx.approvals, "test", %{}, "Pay rent")
    {_bot, fake} = start_bot(ctx, [%{"next_batch" => "s1"}, message("!owner:test", @owner, "approve #{item.id}")])
    assert_receive :ran, 3_000
    refute_received {:asked, _}
    {"PUT", _, body} = sent(fake, "!owner:test")
    assert body["body"] == "done"
  end

  test "a new approval request goes to the owner room and to the nudge", ctx do
    {_bot, fake} = start_bot(ctx, [%{"next_batch" => "s1"}])
    FakeHomeserver.await(fake, fn {_, p, _} -> p =~ "createRoom" end)
    Process.sleep(100)
    {:ok, item} = Approvals.request(ctx.approvals, "test", %{}, "Pay rent")
    {"PUT", _, body} = sent(fake, "!owner:test")
    assert body["body"] =~ "approve #{item.id}"
    assert_receive {:nudge, "LUNA needs your approval. Open Matrix."}
  end

  test "an invite from the owner is joined, an invite from another user is not", ctx do
    invite = fn room, sender ->
      %{"invite_state" => %{"events" => [%{"type" => "m.room.member", "state_key" => "@luna:test",
        "sender" => sender, "content" => %{"membership" => "invite"}}]}}
      |> then(&%{"next_batch" => "s1", "rooms" => %{"invite" => %{room => &1}}})
    end

    {_bot, fake} = start_bot(ctx, [invite.("!a:test", @owner), invite.("!b:test", "@stranger:test")])
    assert FakeHomeserver.await(fake, fn {_, p, _} -> p =~ "/join/" end)
    Process.sleep(300)
    joins = for {"POST", p, _} <- FakeHomeserver.requests(fake), p =~ "/join/", do: p
    assert joins == ["/_matrix/client/v3/join/%21a%3Atest"]
  end

  test "the bot does not write to an encrypted room, and tells the owner", ctx do
    encrypted = %{"next_batch" => "s1", "rooms" => %{"join" => %{"!enc:test" => %{
      "state" => %{"events" => [%{"type" => "m.room.encryption", "content" => %{}}]},
      "timeline" => %{"events" => [%{"type" => "m.room.encrypted", "sender" => @owner, "origin_server_ts" => now(), "content" => %{}}]}}}}}
    {_bot, fake} = start_bot(ctx, [%{"next_batch" => "s0"}, encrypted, message("!enc:test", @owner, "hi")])
    {"PUT", _, body} = sent(fake, "!owner:test")
    assert body["body"] =~ "encrypted"
    Process.sleep(300)
    refute Enum.any?(FakeHomeserver.requests(fake), fn {m, p, _} -> m == "PUT" and p =~ "%21enc%3Atest/send" end)
    assert File.read!(ctx.audit) =~ "matrix.send_refused_encrypted"
  end

  test "a bad access token causes one new login", ctx do
    File.write!(Path.join(ctx.tmp, "matrix-session.json"), ~s({"access_token": "old"}))
    {_bot, fake} = start_bot(ctx, [%{"next_batch" => "s1"}, {:status, 401}])
    assert FakeHomeserver.await(fake, fn {m, p, _} -> m == "POST" and p =~ "/login" end)
    assert File.read!(Path.join(ctx.tmp, "matrix-session.json")) =~ "token-1"
  end
end
