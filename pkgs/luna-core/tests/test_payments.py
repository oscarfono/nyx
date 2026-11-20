import asyncio
import json
from datetime import UTC, date, datetime, timedelta

import httpx
import pytest

from luna_core.approvals import Approvals
from luna_core.audit import AuditLog
from luna_core.payment_tools import build_payment_tools
from luna_core.payments import PaymentError, PaymentLog, Payments, WiseClient, WiseSettings, check, clean_reference

TODAY = date(2026, 11, 23)


def settings(mode):
    return WiseSettings.from_json(json.dumps({
        "mode": mode, "sandbox": True, "maxPerPayment": 100, "maxPerDay": 150,
        "payees": {"landlord": {"recipientId": 42, "currency": "AUD", "maxPerPayment": 80}},
    }))


class FakeWise:
    def __init__(self):
        self.calls = []
        self.state = "incoming_payment_waiting"

    def handler(self, request):
        path = request.url.path
        self.calls.append((request.method, path))
        if path == "/v1/profiles":
            return httpx.Response(200, json=[{"id": 7, "type": "PERSONAL"}])
        if path.endswith("/quotes"):
            return httpx.Response(200, json={"id": "q-1"})
        if path == "/v1/transfers":
            body = json.loads(request.content)
            assert body["targetAccount"] == 42 and body["quoteUuid"] == "q-1"
            return httpx.Response(200, json={"id": 555, "status": "incoming_payment_waiting"})
        if path == "/v1/transfers/555" and request.method == "GET":
            return httpx.Response(200, json={"id": 555, "status": self.state})
        if path == "/v1/transfers/555/cancel":
            self.state = "cancelled"
            return httpx.Response(200, json={"id": 555, "status": "cancelled"})
        if path.endswith("/payments"):
            return httpx.Response(200, json={"status": "COMPLETED"})
        return httpx.Response(404)


class Clock:
    def __init__(self):
        self.value = datetime(2026, 11, 23, 9, 0, tzinfo=UTC)

    def __call__(self):
        return self.value


def make(tmp_path, mode):
    fake, clock, told = FakeWise(), Clock(), []
    client = WiseClient("token", True, transport=httpx.MockTransport(fake.handler))
    audit = AuditLog(tmp_path / "audit.jsonl")
    payments = Payments(settings(mode), PaymentLog(tmp_path / "payments.jsonl"), audit, client, lambda: TODAY, clock)

    async def notify(text):
        told.append(text)

    payments.notify = notify
    return payments, fake, clock, told


def run(coro):
    return asyncio.run(coro)


@pytest.mark.parametrize("payee, amount, currency, message", [
    ("stranger", "10", "AUD", "not on the allowlist"),
    ("landlord", "10", "NZD", "takes AUD"),
    ("landlord", "0", "AUD", "more than zero"),
    ("landlord", "90", "AUD", "limit of AUD 80"),
    ("landlord", "abc", "AUD", "not an amount"),
])
def test_controls(tmp_path, payee, amount, currency, message):
    payments, *_ = make(tmp_path, "draft")
    with pytest.raises(PaymentError, match=message):
        check(payments.settings, payments.log, payee, amount, currency, TODAY)


def test_off_refuses(tmp_path):
    payments, *_ = make(tmp_path, "off")
    with pytest.raises(PaymentError, match="off"):
        check(payments.settings, payments.log, "landlord", "10", "AUD", TODAY)


def test_dry_run_calls_nothing(tmp_path):
    payments, fake, *_ = make(tmp_path, "dry-run")
    assert "Dry run" in run(payments.request("landlord", "50", "AUD", "Rent", "k-1"))
    assert fake.calls == []


def test_draft_makes_a_transfer_and_never_funds(tmp_path):
    payments, fake, _, told = make(tmp_path, "draft")
    text = run(payments.request("landlord", "50", "AUD", "Rent", "k-1"))
    assert "Approve in the Wise app" in text and told == [text]
    assert ("POST", "/v1/transfers") in fake.calls
    assert not any(path.endswith("/payments") for _, path in fake.calls)


def test_drafts_count_toward_the_day_limit(tmp_path):
    payments, *_ = make(tmp_path, "draft")
    run(payments.request("landlord", "80", "AUD", "Rent", "k-1"))
    with pytest.raises(PaymentError, match="limit per day"):
        check(payments.settings, payments.log, "landlord", "80", "AUD", TODAY)


def test_watch_reports_funding(tmp_path):
    payments, fake, _, told = make(tmp_path, "draft")
    run(payments.request("landlord", "50", "AUD", "Rent", "k-1"))
    fake.state = "processing"
    run(payments.watch_once())
    assert "You approved" in told[-1]
    assert payments.log.latest()["k-1"]["status"] == "funded"
    run(payments.watch_once())
    assert len(told) == 2


def test_watch_cancels_after_24_hours(tmp_path):
    payments, fake, clock, told = make(tmp_path, "draft")
    run(payments.request("landlord", "50", "AUD", "Rent", "k-1"))
    clock.value += timedelta(hours=23)
    run(payments.watch_once())
    assert ("PUT", "/v1/transfers/555/cancel") not in fake.calls
    clock.value += timedelta(hours=2)
    run(payments.watch_once())
    assert ("PUT", "/v1/transfers/555/cancel") in fake.calls
    assert "Nobody funded it" in told[-1]
    assert payments.log.total_for(TODAY, "AUD") == 0


def test_watch_sees_a_cancel_in_the_app(tmp_path):
    payments, fake, _, told = make(tmp_path, "draft")
    run(payments.request("landlord", "50", "AUD", "Rent", "k-1"))
    fake.state = "cancelled"
    run(payments.watch_once())
    assert "You cancelled" in told[-1]


def test_auto_needs_a_matrix_approval(tmp_path):
    payments, fake, *_ = make(tmp_path, "auto")
    (tmp_path / "approvals").mkdir()
    approvals = Approvals(tmp_path / "approvals", payments.audit)
    tools = build_payment_tools(payments, approvals, payments.audit)
    assert tools
    item = run(approvals.request("wise_transfer", {"payee": "landlord", "amount": "50.00", "currency": "AUD",
                                                   "reference": "Rent", "key": "k-1"}, "test"))
    assert fake.calls == []
    assert "Sent AUD 50.00" in run(approvals.approve(item.id))
    assert ("POST", "/v3/profiles/7/transfers/555/payments") in fake.calls


def test_reference_is_cleaned():
    assert clean_reference("Rent; DROP TABLE <x> 2026-11") == "Rent DROP TABLE x"
