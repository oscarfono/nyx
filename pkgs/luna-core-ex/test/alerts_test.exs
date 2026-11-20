defmodule LunaCore.AlertsTest do
  use ExUnit.Case, async: true

  alias LunaCore.Alerts

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    test = self()
    {:ok, alerts} = Alerts.start_link(audit: Path.join(tmp, "audit.jsonl"), send: &send(test, {:sent, &1}), max: 2, name: nil)
    %{alerts: alerts, tmp: tmp}
  end

  test "an alert goes to the owner, on one line", %{alerts: a} do
    assert Alerts.alert(a, "luna-core failed\n(core-dump)") == :sent
    assert_received {:sent, "**Blue team:** luna-core failed (core-dump)"}
  end

  test "a notice keeps its lines, and has its own limit", %{alerts: a} do
    assert Alerts.notice(a, "**Security brief**\n\n- line one\n- line two") == :sent
    assert_received {:sent, "**Security brief**\n\n- line one\n- line two"}
    for _ <- 1..4, do: assert(Alerts.notice(a, "x") == :sent)
    assert Alerts.notice(a, "sixth") == :logged
    # The notices do not use the alert limit.
    assert Alerts.alert(a, "still works") == :sent
  end

  test "over the limit: one notice, then the audit log only", %{alerts: a, tmp: tmp} do
    assert Alerts.alert(a, "one") == :sent
    assert Alerts.alert(a, "two") == :sent
    assert Alerts.alert(a, "three") == :paused
    assert Alerts.alert(a, "four") == :logged
    assert_received {:sent, "**Blue team:** one"}
    assert_received {:sent, "**Blue team:** two"}
    assert_received {:sent, "**Blue team:** too many alerts" <> _}
    refute_received {:sent, _}
    assert File.read!(Path.join(tmp, "audit.jsonl")) =~ "four"
  end
end
