"""The payment tool. In draft mode the Wise app is the approval; in auto mode, Matrix."""

from __future__ import annotations

from typing import Any

from anthropic import beta_async_tool

from .approvals import Approvals
from .audit import AuditLog
from .payments import PaymentError, Payments, check, clean_reference, payment_key


def build_payment_tools(payments: Payments, approvals: Approvals, audit: AuditLog) -> list[Any]:
    approvals.register("wise_transfer", payments.execute)

    @beta_async_tool
    async def payment_request(payee: str, amount: str, currency: str, reference: str, reason: str) -> str:
        """Request a payment from the Wise float to a payee on the allowlist.

        No money moves now. Coops approves in the Wise app (draft mode) or in Matrix (auto mode).

        Args:
            payee: The name of the payee on the allowlist.
            amount: The amount, for example "45.00".
            currency: The currency code of the payee, for example "AUD".
            reference: The payment reference. Wise keeps 18 letters, digits and spaces.
            reason: Why LUNA asks for this payment, in one sentence.
        """
        audit.write("tool", name="payment_request", payee=payee, amount=amount, currency=currency, reason=reason)
        try:
            if payments.settings.mode in ("dry-run", "draft"):
                return await payments.request(payee, amount, currency, reference, payment_key())
            target, value = check(payments.settings, payments.log, payee, amount, currency, payments.today())
        except PaymentError as error:
            return f"Refused: {error}"
        ref = clean_reference(reference)
        params = {"payee": target.name, "amount": str(value), "currency": target.currency,
                  "reference": ref, "key": payment_key()}
        item = await approvals.request("wise_transfer", params,
                                       payments.summary(target.name, value, target.currency, ref, reason))
        return f"Approval request {item.id} sent to Coops in Matrix."

    return [payment_request]
