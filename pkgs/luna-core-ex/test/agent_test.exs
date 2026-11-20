defmodule LunaCore.AgentTest do
  use ExUnit.Case, async: true

  alias LunaCore.{Agent, FakeClaude, Memory, Tools}
  import LunaCore.FakeClaude, only: [message: 2, text: 1, tool_use: 3]

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    root = Path.join(tmp, "memory")
    File.mkdir_p!(Path.join(root, "money"))
    for {k, v} <- [{"GIT_CONFIG_GLOBAL", "/dev/null"}, {"GIT_CONFIG_NOSYSTEM", "1"},
                   {"GIT_AUTHOR_NAME", "t"}, {"GIT_COMMITTER_NAME", "t"},
                   {"GIT_AUTHOR_EMAIL", "t@example.com"}, {"GIT_COMMITTER_EMAIL", "t@example.com"}],
        do: System.put_env(k, v)
    {_, 0} = System.cmd("git", ["init", "--quiet", root])
    File.write!(Path.join(root, "notes.org"), "* Notes\nBali is cheap in March.\n")
    File.write!(Path.join(root, "money.org"), "* Money\nSafe to spend: 420\n")
    {_, 0} = System.cmd("git", ["-C", root, "add", "-A"])
    {_, 0} = System.cmd("git", ["-C", root, "commit", "--quiet", "-m", "seed"])
    audit = Path.join(tmp, "audit.jsonl")
    {:ok, memory} = Memory.start_link(root: root, audit: audit, remote: false, name: nil)
    tools = Tools.memory_tools(memory, audit, fn -> ~N[2026-11-21 07:00:00] end)
    %{audit: audit, tools: tools, root: root}
  end

  defp start_agent(ctx, replies) do
    fake = FakeClaude.start(replies)

    {:ok, agent} =
      Agent.start_link(api_key: "test-key", audit: ctx.audit, tools: ctx.tools, base_url: fake.base_url,
                       zone: "Australia/Perth", effort: "medium", max_retries: 0, name: nil)

    {agent, fake}
  end

  test "a plain reply, and the shape of the request", ctx do
    {agent, fake} = start_agent(ctx, [{200, message("end_turn", [text("Hi, Coops.")])}])
    assert Agent.ask(agent, "hello") == "Hi, Coops."

    [%{body: body, headers: headers}] = FakeClaude.requests(fake)
    assert headers["anthropic-version"] == "2026-10-21"
    assert headers["x-api-key"] == "test-key"
    assert headers["anthropic-beta"] == "server-side-fallback-2026-07-01,mid-conversation-tool-changes-2026-07-01"
    assert body["model"] == "claude-opus-5-5"
    assert body["fallbacks"] == "default"
    assert body["thinking"] == %{"type" => "adaptive"}
    assert body["output_config"] == %{"effort" => "medium"}
    assert Enum.map(body["tools"], & &1["name"]) == ~w(memory_files memory_search memory_read memory_append web_search web_fetch)
    [%{"role" => "user", "content" => content}] = body["messages"]
    assert content =~ ~r/^\[\w+day 20\d\d-\d\d-\d\d \d\d:\d\d AWST\]\nhello$/
  end

  test "the tool loop runs a tool and sends the result", ctx do
    {agent, fake} =
      start_agent(ctx, [
        {200, message("tool_use", [text("Let me look."), tool_use("toolu_1", "memory_read", %{"path" => "notes.org"})])},
        {200, message("end_turn", [text("Bali is cheap in March.")])}
      ])

    assert Agent.ask(agent, "where is cheap?") == "Bali is cheap in March."
    [_, %{body: second}] = FakeClaude.requests(fake)
    [_, %{"role" => "assistant"}, %{"role" => "user", "content" => [result]}] = second["messages"]
    assert result["tool_use_id"] == "toolu_1"
    assert result["content"] =~ "Bali is cheap"
  end

  test "money data taints the conversation, and the next request removes the web tools", ctx do
    {agent, fake} =
      start_agent(ctx, [
        {200, message("tool_use", [tool_use("toolu_1", "memory_read", %{"path" => "money.org"})])},
        {200, message("end_turn", [text("420.")])},
        {200, message("end_turn", [text("Still no web.")])}
      ])

    assert Agent.ask(agent, "safe to spend?") == "420."
    assert Agent.ask(agent, "and the web?") == "Still no web."
    [_, %{body: second}, %{body: third}] = FakeClaude.requests(fake)
    removals = Enum.filter(second["messages"], &(&1["role"] == "system"))
    assert [%{"content" => blocks}] = removals
    assert Enum.map(blocks, & &1["tool"]["name"]) == ["web_search", "web_fetch"]
    # One removal for the whole conversation.
    assert length(Enum.filter(third["messages"], &(&1["role"] == "system"))) == 1
    assert File.read!(ctx.audit) =~ "agent.tainted"
  end

  test "a tainted conversation cannot write a clean memory file", ctx do
    {agent, _fake} =
      start_agent(ctx, [
        {200, message("tool_use", [tool_use("t1", "memory_read", %{"path" => "money.org"})])},
        {200, message("tool_use", [tool_use("t2", "memory_append", %{"path" => "notes.org", "heading" => "Leak", "body" => "420"})])},
        {200, message("end_turn", [text("I cannot write that.")])}
      ])

    Agent.ask(agent, "copy the money to notes")
    refute File.read!(Path.join(ctx.root, "notes.org")) =~ "Leak"
    assert File.read!(ctx.audit) =~ "tool.refused"
  end

  test "a paused turn goes back without a new user message", ctx do
    paused = message("pause_turn", [%{"type" => "server_tool_use", "id" => "srvtoolu_1", "name" => "web_search", "input" => %{"query" => "x"}}])
    {agent, fake} = start_agent(ctx, [{200, paused}, {200, message("end_turn", [text("Found it.")])}])
    assert Agent.ask(agent, "search") == "Found it."
    [_, %{body: second}] = FakeClaude.requests(fake)
    assert Enum.map(second["messages"], & &1["role"]) == ["user", "assistant"]
  end

  test "the paused turns stop after five restarts", ctx do
    paused = message("pause_turn", [text("Still searching.")])
    {agent, fake} = start_agent(ctx, List.duplicate({200, paused}, 10))
    assert Agent.ask(agent, "search") == "Still searching."
    assert length(FakeClaude.requests(fake)) == 6
  end

  test "an unknown tool gets an error result", ctx do
    {agent, fake} =
      start_agent(ctx, [
        {200, message("tool_use", [tool_use("t1", "send_money", %{})])},
        {200, message("end_turn", [text("I have no such tool.")])}
      ])

    Agent.ask(agent, "pay")
    [_, %{body: second}] = FakeClaude.requests(fake)
    %{"content" => [result]} = List.last(second["messages"])
    assert result["is_error"] == true
  end

  test "the errors from the API become plain replies", ctx do
    {agent, _} = start_agent(ctx, [{429, %{}}])
    assert Agent.ask(agent, "x") =~ "rate limit"

    {agent, _} = start_agent(ctx, [{400, %{"error" => %{"message" => "bad history"}}}])
    assert Agent.ask(agent, "x") =~ "started a new conversation. (bad history)"
    assert Agent.transcript(agent) == []
  end

  test "a refusal and a reply at the length limit", ctx do
    {agent, _} = start_agent(ctx, [{200, message("refusal", [])}, {200, message("max_tokens", [text("Long")])}])
    assert Agent.ask(agent, "x") == "The model declined this request."
    assert Agent.ask(agent, "y") == "Long\n\n[The reply stopped at the length limit.]"
  end

  test "the transcript has the text only, without the time stamp", ctx do
    {agent, _} =
      start_agent(ctx, [
        {200, message("tool_use", [tool_use("t1", "memory_files", %{})])},
        {200, message("end_turn", [%{"type" => "thinking", "thinking" => ""}, text("Two files.")])}
      ])

    Agent.ask(agent, "files?", [{"image/png", "AA=="}])
    assert Agent.transcript(agent) == [%{role: "user", text: "files?\n[image]"}, %{role: "assistant", text: "Two files."}]
  end
end
