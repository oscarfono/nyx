defmodule LunaCore.ApprovalsTest do
  use ExUnit.Case, async: true

  alias LunaCore.Approvals

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    dir = Path.join(tmp, "approvals")
    File.mkdir_p!(dir)
    audit = Path.join(tmp, "audit.jsonl")
    test = self()
    {:ok, server} = Approvals.start_link(dir: dir, audit: audit, name: nil)
    :ok = Approvals.register(server, "test", fn params -> send(test, {:ran, params}) && "done" end)
    %{server: server, dir: dir, audit: audit}
  end

  test "approve runs the executor once", %{server: s} do
    {:ok, item} = Approvals.request(s, "test", %{"x" => 1}, "Test action")
    assert Approvals.approve(s, item.id) == "done"
    assert_received {:ran, %{"x" => 1}}
    assert Approvals.approve(s, item.id) =~ "no request"
    refute_received {:ran, _}
  end

  test "deny does not run the executor", %{server: s} do
    {:ok, item} = Approvals.request(s, "test", %{}, "Test action")
    assert Approvals.deny(s, item.id) =~ "Denied"
    refute_received {:ran, _}
    assert Approvals.pending(s) == []
  end

  test "an expired request does not run", %{server: s, dir: dir} do
    {:ok, item} = Approvals.request(s, "test", %{}, "Old action")
    path = Path.join(dir, item.id <> ".json")
    old = DateTime.utc_now() |> DateTime.add(-2, :day) |> DateTime.to_iso8601()
    File.write!(path, path |> File.read!() |> Jason.decode!() |> Map.put("created", old) |> Jason.encode!())
    assert Approvals.approve(s, item.id) =~ "expired"
    refute_received {:ran, _}
  end

  test "a bad request ID is refused", %{server: s} do
    assert Approvals.approve(s, "../../etc/passwd") =~ "no request"
    refute_received {:ran, _}
  end

  test "an unknown action is refused", %{server: s} do
    assert {:error, _} = Approvals.request(s, "transfer_money", %{}, "No executor")
  end

  test "two approvals at the same time run the executor once", %{server: s} do
    {:ok, item} = Approvals.request(s, "test", %{}, "Race")
    results = 1..5 |> Enum.map(fn _ -> Task.async(fn -> Approvals.approve(s, item.id) end) end) |> Task.await_many()
    assert Enum.count(results, &(&1 == "done")) == 1
  end

  test "the audit log has one sorted JSON line for each event", %{server: s, audit: audit} do
    {:ok, item} = Approvals.request(s, "test", %{}, "Logged")
    Approvals.deny(s, item.id)
    lines = audit |> File.read!() |> String.split("\n", trim: true)
    assert Enum.map(lines, &Jason.decode!(&1)["event"]) == ["approval.requested", "approval.denied"]
    assert hd(lines) =~ ~r/^\{"action":/
  end
end
