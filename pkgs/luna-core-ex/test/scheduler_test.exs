defmodule LunaCore.SchedulerTest do
  use ExUnit.Case, async: true

  alias LunaCore.Scheduler
  alias LunaCore.Scheduler.{Brief, Sync}

  @moduletag :tmp_dir

  defp perth(naive), do: DateTime.from_naive!(naive, "Australia/Perth")

  test "the next run is today before the time" do
    assert Scheduler.next_run(perth(~N[2026-11-20 06:00:00]), ~T[07:00:00]) == perth(~N[2026-11-20 07:00:00])
  end

  test "the next run is tomorrow after the time" do
    assert Scheduler.next_run(perth(~N[2026-11-20 08:00:00]), ~T[07:00:00]) == perth(~N[2026-11-21 07:00:00])
  end

  test "the next run is tomorrow at the time exactly" do
    assert Scheduler.next_run(perth(~N[2026-11-20 07:00:00]), ~T[07:00:00]) == perth(~N[2026-11-21 07:00:00])
  end

  test "the next run in a zone with daylight saving takes a valid time" do
    # Sydney skips 02:00 to 03:00 on 2026-10-04.
    now = DateTime.from_naive!(~N[2026-10-03 23:00:00], "Australia/Sydney")
    next = Scheduler.next_run(now, ~T[02:30:00])
    assert DateTime.to_date(next) == ~D[2026-10-04]
    assert next.hour == 3
  end

  test "compose puts the notice first and the money last" do
    assert Scheduler.compose("Brief.", "Notice.", "Money.") == "Notice.\n\nBrief.\n\nMoney."
    assert Scheduler.compose("Brief.", nil, nil) == "Brief."
  end

  test "the brief goes to the owner with the system notice", %{tmp_dir: tmp} do
    audit = Path.join(tmp, "audit.jsonl")
    test = self()

    opts = [
      zone: "Australia/Perth", audit: audit,
      ask: fn prompt -> send(test, {:prompt, prompt}) && "Day 3 of 14 on site." end,
      send: fn text -> send(test, {:sent, text}) end,
      notice: fn _date -> "System notice: old nixpkgs." end
    ]

    assert Brief.run_once(opts) == :ok
    assert_received {:prompt, prompt}
    assert prompt =~ "morning brief"
    assert_received {:sent, "System notice: old nixpkgs.\n\nDay 3 of 14 on site."}
    assert File.read!(audit) =~ "brief.sent"
  end

  test "a failed brief goes to the audit log, and run_once does not crash", %{tmp_dir: tmp} do
    audit = Path.join(tmp, "audit.jsonl")
    opts = [audit: audit, ask: fn _ -> raise "API down" end, send: fn _ -> :ok end]
    assert Brief.run_once(opts) == :error
    assert File.read!(audit) =~ "brief.error"
  end

  test "a failed memory sync goes to the audit log", %{tmp_dir: tmp} do
    audit = Path.join(tmp, "audit.jsonl")
    # A working copy with no remote: git pull fails.
    root = Path.join(tmp, "memory")
    {_, 0} = System.cmd("git", ["init", "--quiet", root])
    {:ok, memory} = LunaCore.Memory.start_link(root: root, audit: audit, remote: true, name: nil)
    Sync.run_once(memory: memory, audit: audit)
    assert File.read!(audit) =~ "memory.sync_error"
  end
end
