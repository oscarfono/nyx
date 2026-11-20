defmodule LunaCore.MemoryTest do
  use ExUnit.Case, async: true

  alias LunaCore.Memory

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    root = Path.join(tmp, "memory")
    File.mkdir_p!(root)
    # The git config of the user (commit signing, hooks) must not change a test.
    env = [{"GIT_CONFIG_GLOBAL", "/dev/null"}, {"GIT_CONFIG_NOSYSTEM", "1"},
           {"GIT_AUTHOR_NAME", "test"}, {"GIT_COMMITTER_NAME", "test"},
           {"GIT_AUTHOR_EMAIL", "test@example.com"}, {"GIT_COMMITTER_EMAIL", "test@example.com"}]
    for {k, v} <- env, do: System.put_env(k, v)
    {_, 0} = System.cmd("git", ["init", "--quiet", root])
    File.write!(Path.join(root, "notes.org"), "* Notes\nThe base costs AUD 900 per month.\n")
    {_, 0} = System.cmd("git", ["-C", root, "add", "-A"])
    {_, 0} = System.cmd("git", ["-C", root, "commit", "--quiet", "-m", "seed"])
    {:ok, server} = Memory.start_link(root: root, audit: Path.join(tmp, "audit.jsonl"), remote: false, name: nil)
    %{server: server, root: root, tmp: tmp}
  end

  for path <- ["/etc/passwd", "../outside.org", ".git/config", "notes.txt", "a/../../x.org", "a/../.git/x.org"] do
    test "#{path} is refused", %{root: root} do
      assert {:error, _} = Memory.resolve(root, unquote(path))
    end
  end

  test "a path through a symlink is refused", %{root: root, tmp: tmp} do
    File.mkdir_p!(Path.join(tmp, "outside"))
    File.write!(Path.join(tmp, "outside/secret.org"), "secret")
    File.ln_s!(Path.join(tmp, "outside"), Path.join(root, "link"))
    assert {:error, _} = Memory.resolve(root, "link/secret.org")
  end

  test "the search ignores case", %{server: s} do
    assert Memory.search(s, "BASE COSTS") == {:ok, ["notes.org:2: The base costs AUD 900 per month."]}
  end

  test "append makes a commit", %{server: s, root: root} do
    {:ok, _} = Memory.append(s, "travel.org", "Bali in March", "- Budget: AUD 60 per night", ~N[2026-11-20 07:00:00])
    {:ok, text} = Memory.read(s, "travel.org")
    assert text =~ "* Bali in March"
    assert text =~ ":CREATED: [2026-11-20 Fri 07:00]"
    {log, 0} = System.cmd("git", ["-C", root, "log", "--oneline"])
    assert log =~ "Bali in March"
  end

  test "the file list has org and journal files only", %{server: s, root: root} do
    File.write!(Path.join(root, "x.txt"), "no")
    File.mkdir_p!(Path.join(root, "money"))
    File.write!(Path.join(root, "money/main.journal"), "")
    assert Memory.files(s) == ["money/main.journal", "notes.org"]
  end
end
