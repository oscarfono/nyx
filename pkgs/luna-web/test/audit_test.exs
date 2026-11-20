defmodule LunaWeb.AuditTest do
  use LunaWeb.Case, async: true

  alias LunaWeb.Repo

  setup do
    :ok = LunaWeb.Audit.write("test.event", %{"n" => 1})
  end

  test "the audit log refuses UPDATE" do
    assert_raise Postgrex.Error, ~r/refuses UPDATE/, fn ->
      Repo.query!("UPDATE audit_events SET event = 'changed'")
    end
  end

  test "the audit log refuses DELETE" do
    assert_raise Postgrex.Error, ~r/refuses DELETE/, fn ->
      Repo.query!("DELETE FROM audit_events")
    end
  end

  test "the audit log refuses TRUNCATE" do
    assert_raise Postgrex.Error, ~r/refuses TRUNCATE/, fn ->
      Repo.query!("TRUNCATE audit_events")
    end
  end
end
