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
