defmodule LunaCore.MainTest do
  # The whole core, with the named processes, so this test does not run with others that name them.
  use ExUnit.Case, async: false

  alias LunaCore.{Config, FakeClaude, FakeHomeserver, Main}

  @moduletag :tmp_dir

  test "the configuration from the environment" do
    env = %{"LUNA_HOMESERVER" => "http://hs", "LUNA_MATRIX_USER" => "@luna:x", "LUNA_OWNER" => "@coops:x",
            "LUNA_ANTHROPIC_API_KEY" => "k", "LUNA_MATRIX_PASSWORD" => "p", "LUNA_OWNER_TIMEZONE" => "UTC",
            "LUNA_BRIEF_TIME" => "07:30"}
    config = Config.load(env)
    assert config.owner_timezone == "Etc/UTC"
    assert config.brief_time == ~T[07:30:00]
    assert config.money_enabled == false
    assert config.audit_file == "/var/lib/luna/audit/audit.jsonl"
    assert_raise RuntimeError, ~r/LUNA_OWNER/, fn -> Config.load(Map.delete(env, "LUNA_OWNER")) end
  end

  test "the whole core starts: Matrix, the agent and the core API", %{tmp_dir: tmp} do
    for {k, v} <- [{"GIT_CONFIG_GLOBAL", "/dev/null"}, {"GIT_CONFIG_NOSYSTEM", "1"}, {"GIT_AUTHOR_NAME", "t"},
                   {"GIT_COMMITTER_NAME", "t"}, {"GIT_AUTHOR_EMAIL", "t@example.com"}, {"GIT_COMMITTER_EMAIL", "t@example.com"}],
        do: System.put_env(k, v)

    state = Path.join(tmp, "state")
    for d <- ["approvals", "audit", "inbox", "memory"], do: File.mkdir_p!(Path.join(state, d))
    {_, 0} = System.cmd("git", ["init", "--quiet", Path.join(state, "memory")])
    claude = FakeClaude.start([{200, FakeClaude.message("end_turn", [FakeClaude.text("Hi from Elixir.")])}])
    hs = FakeHomeserver.start([%{"next_batch" => "s1"}])
    socket = Path.join(System.tmp_dir!(), "luna-main-#{System.unique_integer([:positive])}.sock")

    config =
      Config.load(%{"LUNA_STATE_DIR" => state, "LUNA_HOMESERVER" => hs.url, "LUNA_MATRIX_USER" => "@luna:test",
                    "LUNA_OWNER" => "@coops:test", "LUNA_ANTHROPIC_API_KEY" => "k", "LUNA_MATRIX_PASSWORD" => "p",
                    "LUNA_API_SOCKET" => socket})
      |> Map.merge(%{remote: false, agent_opts: [base_url: claude.base_url, max_retries: 0]})

    {:ok, sup} = Supervisor.start_link(Main.children(config), strategy: :one_for_one)
    on_exit(fn -> File.rm(socket) end)

    assert FakeHomeserver.await(hs, fn {_, p, _} -> p =~ "createRoom" end)
    {:ok, %{status: 200, body: body}} = Req.post("http://core/api/chat", json: %{text: "hi"}, unix_socket: socket, retry: false)
    assert body["reply"] == "Hi from Elixir."
    {:ok, %{body: system}} = Req.get("http://core/api/system", unix_socket: socket, retry: false)
    assert system["settings"]["wise_mode"] == "off"
    Supervisor.stop(sup)
    audit = File.read!(config.audit_file)
    assert audit =~ "matrix.ready" and audit =~ ~s("core":"elixir")
  end
end
