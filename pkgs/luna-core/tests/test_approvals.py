import asyncio
import json
from datetime import UTC, datetime, timedelta

from luna_core.approvals import Approvals
from luna_core.audit import AuditLog


def make(tmp_path):
    (tmp_path / "approvals").mkdir()
    audit = AuditLog(tmp_path / "audit.jsonl")
    approvals = Approvals(tmp_path / "approvals", audit)
    calls = []

    async def executor(params):
        calls.append(params)
        return "done"

    approvals.register("test", executor)
    return approvals, calls


def test_approve_runs_the_executor_once(tmp_path):
    approvals, calls = make(tmp_path)
    item = asyncio.run(approvals.request("test", {"x": 1}, "Test action"))
    assert asyncio.run(approvals.approve(item.id)) == "done"
    assert calls == [{"x": 1}]
    assert "no request" in asyncio.run(approvals.approve(item.id))
    assert calls == [{"x": 1}]


def test_deny_does_not_run_the_executor(tmp_path):
    approvals, calls = make(tmp_path)
    item = asyncio.run(approvals.request("test", {}, "Test action"))
    assert "Denied" in approvals.deny(item.id)
    assert calls == []
    assert approvals.pending() == []


def test_expired_request_does_not_run(tmp_path):
    approvals, calls = make(tmp_path)
    item = asyncio.run(approvals.request("test", {}, "Old action"))
    path = tmp_path / "approvals" / f"{item.id}.json"
    data = json.loads(path.read_text())
    data["created"] = (datetime.now(UTC) - timedelta(days=2)).isoformat()
    path.write_text(json.dumps(data))
    assert "expired" in asyncio.run(approvals.approve(item.id))
    assert calls == []


def test_bad_request_id_is_refused(tmp_path):
    approvals, calls = make(tmp_path)
    assert "no request" in asyncio.run(approvals.approve("../../etc/passwd"))
    assert calls == []


def test_unknown_action_is_refused(tmp_path):
    approvals, _ = make(tmp_path)
    try:
        asyncio.run(approvals.request("transfer_money", {}, "No executor"))
    except ValueError:
        return
    raise AssertionError("The request for an unknown action did not fail.")
