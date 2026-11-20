"""Wise float payments: limits, the payee allowlist, the Wise client, and the executor."""

from __future__ import annotations

import json
import re
import uuid
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any

import httpx

from .audit import AuditLog

MODES = ("off", "dry-run", "draft", "auto")
DRAFT_TTL = timedelta(hours=24)
# Statuses that do not count toward the day total.
CLOSED = frozenset({"failed", "cancelled", "expired"})
# Wise statuses after funding. Refer to the Wise transfer status list.
FUNDED = frozenset({"processing", "funds_converted", "outgoing_payment_sent"})
_REFERENCE = re.compile(r"[^A-Za-z0-9 ]")


class PaymentError(Exception):
    """The payment is not permitted, or Wise refused the payment."""


@dataclass(frozen=True)
class Payee:
    name: str
    recipient_id: int
    currency: str
    max_per_payment: Decimal


@dataclass(frozen=True)
class WiseSettings:
    mode: str
    sandbox: bool
    profile_type: str
    max_per_payment: Decimal
    max_per_day: Decimal
    payees: dict[str, Payee]

    @classmethod
    def from_json(cls, text: str) -> WiseSettings:
        data = json.loads(text)
        mode = data.get("mode", "off")
        if mode not in MODES:
            raise PaymentError(f"The Wise mode {mode!r} is not one of {', '.join(MODES)}.")
        payees = {
            name: Payee(name, int(p["recipientId"]), p["currency"].upper(), Decimal(str(p["maxPerPayment"])))
            for name, p in data.get("payees", {}).items()
        }
        return cls(
            mode=mode,
            sandbox=bool(data.get("sandbox", True)),
            profile_type=data.get("profileType", "personal").lower(),
            max_per_payment=Decimal(str(data.get("maxPerPayment", 100))),
            max_per_day=Decimal(str(data.get("maxPerDay", 200))),
            payees=payees,
        )


def clean_reference(text: str) -> str:
    """Wise accepts a short reference. Keep letters, digits and spaces."""
    return _REFERENCE.sub("", text).strip()[:18].strip() or "LUNA"


def now_utc() -> datetime:
    return datetime.now(UTC)


class PaymentLog:
    """The append-only record of payments. The last record of a payment is its state."""

    def __init__(self, path: Path) -> None:
        self.path = path

    def latest(self) -> dict[str, dict[str, Any]]:
        if not self.path.exists():
            return {}
        state: dict[str, dict[str, Any]] = {}
        for line in self.path.read_text(encoding="utf-8").splitlines():
            record = json.loads(line)
            previous = state.get(record["id"], {})
            # Keep the time of the first record: the 24-hour limit counts from the request.
            state[record["id"]] = {**previous, **record, "time": previous.get("time", record.get("time"))}
        return state

    def total_for(self, day: date, currency: str) -> Decimal:
        total = Decimal(0)
        for record in self.latest().values():
            if record["day"] == day.isoformat() and record["currency"] == currency and record["status"] not in CLOSED:
                total += Decimal(record["amount"])
        return total

    def write(self, **record: Any) -> None:
        record.setdefault("time", now_utc().isoformat())
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, default=str, sort_keys=True) + "\n")


def check(settings: WiseSettings, log: PaymentLog, payee: str, amount_text: str, currency: str, day: date) -> tuple[Payee, Decimal]:
    """Apply every control. Return the payee and the amount, or raise PaymentError."""
    if settings.mode == "off":
        raise PaymentError("Payments are off.")
    if payee not in settings.payees:
        raise PaymentError(f"{payee!r} is not on the allowlist. Allowed: {', '.join(settings.payees) or 'none'}.")
    target = settings.payees[payee]
    try:
        amount = Decimal(amount_text).quantize(Decimal("0.01"))
    except InvalidOperation as error:
        raise PaymentError(f"{amount_text!r} is not an amount.") from error
    if currency.upper() != target.currency:
        raise PaymentError(f"{payee} takes {target.currency}, not {currency.upper()}.")
    if amount <= 0:
        raise PaymentError("The amount must be more than zero.")
    limit = min(target.max_per_payment, settings.max_per_payment)
    if amount > limit:
        raise PaymentError(f"{target.currency} {amount} is more than the limit of {target.currency} {limit}.")
    spent = log.total_for(day, target.currency)
    if spent + amount > settings.max_per_day:
        raise PaymentError(
            f"The day total would be {target.currency} {spent + amount}. "
            f"The limit per day is {target.currency} {settings.max_per_day}."
        )
    return target, amount


class WiseClient:
    """The few Wise API calls that the float uses."""

    def __init__(self, token: str, sandbox: bool, transport: httpx.AsyncBaseTransport | None = None) -> None:
        base = "https://api.wise-sandbox.com" if sandbox else "https://api.wise.com"
        self.http = httpx.AsyncClient(
            base_url=base, headers={"Authorization": f"Bearer {token}"}, timeout=30, transport=transport
        )

    async def _call(self, method: str, path: str, **kwargs: Any) -> Any:
        response = await self.http.request(method, path, **kwargs)
        if response.status_code >= 400:
            raise PaymentError(f"Wise refused {method} {path}: HTTP {response.status_code} {response.text[:200]}")
        return response.json()

    async def profile_id(self, profile_type: str) -> int:
        for profile in await self._call("GET", "/v1/profiles"):
            if str(profile.get("type", "")).lower() == profile_type:
                return int(profile["id"])
        raise PaymentError(f"No {profile_type} profile on this Wise account.")

    async def quote(self, profile: int, currency: str, amount: Decimal) -> str:
        body = {"sourceCurrency": currency, "targetCurrency": currency, "targetAmount": float(amount)}
        return str((await self._call("POST", f"/v3/profiles/{profile}/quotes", json=body))["id"])

    async def transfer(self, recipient_id: int, quote_id: str, reference: str, key: str) -> dict[str, Any]:
        body = {
            "targetAccount": recipient_id,
            "quoteUuid": quote_id,
            "customerTransactionId": key,
            "details": {"reference": reference},
        }
        return await self._call("POST", "/v1/transfers", json=body)

    async def fund(self, profile: int, transfer_id: int) -> dict[str, Any]:
        return await self._call("POST", f"/v3/profiles/{profile}/transfers/{transfer_id}/payments", json={"type": "BALANCE"})

    async def status(self, transfer_id: int) -> str:
        return str((await self._call("GET", f"/v1/transfers/{transfer_id}"))["status"])

    async def cancel(self, transfer_id: int) -> None:
        await self._call("PUT", f"/v1/transfers/{transfer_id}/cancel")


Notify = Callable[[str], Awaitable[Any]]


class Payments:
    """Make payments within the controls, and watch the transfers that wait for Coops."""

    def __init__(self, settings: WiseSettings, log: PaymentLog, audit: AuditLog,
                 client: WiseClient | None, today: Callable[[], date],
                 now: Callable[[], datetime] = now_utc) -> None:
        self.settings = settings
        self.log = log
        self.audit = audit
        self.client = client
        self.today = today
        self.now = now
        self.notify: Notify | None = None

    async def _tell(self, text: str) -> None:
        if self.notify is not None:
            await self.notify(text)

    def summary(self, payee: str, amount: Decimal, currency: str, reference: str, reason: str) -> str:
        return (f"Pay **{payee}** {currency} {amount}, reference \"{reference}\".\nReason: {reason}\n"
                "Auto: after your approval, LUNA makes and funds the transfer.")

    async def _send(self, params: dict[str, Any], fund: bool) -> dict[str, Any]:
        if self.client is None:
            raise PaymentError("No Wise token. Add wise-api-token to the secrets.")
        target = self.settings.payees[params["payee"]]
        profile = await self.client.profile_id(self.settings.profile_type)
        quote = await self.client.quote(profile, target.currency, Decimal(params["amount"]))
        transfer = await self.client.transfer(target.recipient_id, quote, params["reference"], params["key"])
        if fund:
            await self.client.fund(profile, int(transfer["id"]))
        return transfer

    async def request(self, payee: str, amount: str, currency: str, reference: str, key: str) -> str:
        """The tool path for dry-run and draft modes. Draft: the Wise app is the approval."""
        day = self.today()
        target, value = check(self.settings, self.log, payee, amount, currency, day)
        params = {"payee": target.name, "amount": str(value), "currency": target.currency,
                  "reference": clean_reference(reference), "key": key}
        record = dict(id=key, day=day.isoformat(), payee=target.name, amount=str(value),
                      currency=target.currency, mode=self.settings.mode, time=self.now().isoformat())
        if self.settings.mode == "dry-run":
            self.log.write(**record, status="dry-run")
            return (f"Dry run: LUNA would make a Wise transfer of {target.currency} {value} to {target.name}, "
                    "for you to approve in the Wise app. LUNA sent nothing.")
        try:
            transfer = await self._send(params, fund=False)
        except (PaymentError, httpx.HTTPError) as error:
            self.log.write(**record, status="failed", error=str(error))
            raise PaymentError(str(error)) from error
        self.log.write(**record, status="draft", transfer_id=transfer.get("id"))
        self.audit.write("payment.draft", payee=target.name, amount=str(value), transfer_id=transfer.get("id"))
        text = (f"**Approve in the Wise app:** transfer {transfer.get('id')}, {target.currency} {value} "
                f"to {target.name}. To deny, cancel it in the app or do nothing. "
                "LUNA cancels it after 24 hours.")
        await self._tell(text)
        return text

    async def execute(self, params: dict[str, Any]) -> str:
        """The Matrix approval executor, for auto mode. Check the limits again first."""
        day = self.today()
        target, value = check(self.settings, self.log, params["payee"], params["amount"], params["currency"], day)
        record = dict(id=params["key"], day=day.isoformat(), payee=target.name, amount=str(value),
                      currency=target.currency, mode=self.settings.mode, time=self.now().isoformat())
        try:
            transfer = await self._send(params, fund=True)
        except (PaymentError, httpx.HTTPError) as error:
            self.log.write(**record, status="failed", error=str(error))
            raise
        self.log.write(**record, status="funded", transfer_id=transfer.get("id"))
        self.audit.write("payment.funded", payee=target.name, amount=str(value), transfer_id=transfer.get("id"))
        return f"Sent {target.currency} {value} to {target.name}. Wise transfer {transfer.get('id')}."

    async def watch_once(self) -> None:
        """Report funded drafts. Cancel drafts that wait for more than 24 hours."""
        if self.client is None:
            return
        for key, record in self.log.latest().items():
            if record.get("status") != "draft":
                continue
            transfer_id = int(record["transfer_id"])
            status = await self.client.status(transfer_id)
            label = f"{record['currency']} {record['amount']} to {record['payee']} (transfer {transfer_id})"
            if status in FUNDED:
                self.log.write(id=key, status="funded", wise_status=status)
                self.audit.write("payment.funded", transfer_id=transfer_id)
                await self._tell(f"You approved {label} in the Wise app. Wise is sending it.")
            elif status == "cancelled":
                self.log.write(id=key, status="cancelled")
                await self._tell(f"You cancelled {label}.")
            elif self.now() - datetime.fromisoformat(record["time"]) > DRAFT_TTL:
                await self.client.cancel(transfer_id)
                self.log.write(id=key, status="expired")
                self.audit.write("payment.expired", transfer_id=transfer_id)
                await self._tell(f"LUNA cancelled {label}. Nobody funded it in 24 hours.")


def payment_key() -> str:
    """The idempotency key for one payment. Wise uses it to refuse a second transfer."""
    return str(uuid.uuid4())
