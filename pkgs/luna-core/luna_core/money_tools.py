"""The money tools of the agent. Each tool taints the conversation."""

from __future__ import annotations

from typing import Any

from anthropic import beta_async_tool

from .audit import AuditLog
from .money import Money
from .privacy import Taint


def build_money_tools(money: Money, audit: AuditLog, taint: Taint) -> list[Any]:
    @beta_async_tool
    async def money_summary() -> str:
        """Show the balances, the spend of the last 7 days and the safe-to-spend number. Totals only."""
        taint.mark("money_summary")
        audit.write("tool", name="money_summary")
        return money.summary()

    @beta_async_tool
    async def money_import() -> str:
        """Import the bank CSV files in the inbox. Return counts only."""
        taint.mark("money_import")
        audit.write("tool", name="money_import")
        return money.import_inbox()

    @beta_async_tool
    async def money_unknown(limit: int = 20) -> str:
        """List recent transactions with no category. Use this only when Coops asks to see them.

        Args:
            limit: The maximum number of transactions, 1 to 50.
        """
        taint.mark("money_unknown")
        audit.write("tool", name="money_unknown", limit=limit)
        return money.unknown(max(1, min(limit, 50)))

    @beta_async_tool
    async def money_add_rule(pattern: str, account: str) -> str:
        """Add a category rule. Git records the change.

        Args:
            pattern: A regular expression that matches the description. The match ignores case.
            account: The hledger account, for example expenses:food:groceries.
        """
        taint.mark("money_add_rule")
        audit.write("tool", name="money_add_rule", pattern=pattern, account=account)
        return money.add_rule(pattern, account)

    return [money_summary, money_import, money_unknown, money_add_rule]
