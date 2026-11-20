"""Read, apply and add the category rules in money/categories.org."""

from __future__ import annotations

import re
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path

from .orgtable import tables_by_heading

ACCOUNT = re.compile(r"^(assets|liabilities|income|expenses|equity)(:[a-z0-9][a-z0-9-]*)+$")
UNKNOWN_OUT = "expenses:unknown"
UNKNOWN_IN = "income:unknown"
TABLE = "Rules"


class RuleError(Exception):
    """The rule is not valid."""


@dataclass(frozen=True)
class Rule:
    pattern: re.Pattern[str]
    account: str


def load_rules(path: Path) -> tuple[list[Rule], list[str]]:
    """Return the valid rules and a list of problems."""
    rows = tables_by_heading(path.read_text(encoding="utf-8")).get(TABLE, [])
    rules: list[Rule] = []
    problems: list[str] = []
    for row in rows[1:]:
        if len(row) < 2 or not row[0]:
            continue
        try:
            rules.append(Rule(re.compile(row[0], re.IGNORECASE), _check_account(row[1])))
        except (re.error, RuleError) as error:
            problems.append(f"{row[0]!r}: {error}")
    return rules, problems


def categorise(description: str, amount: Decimal, rules: list[Rule]) -> str:
    for rule in rules:
        if rule.pattern.search(description):
            return rule.account
    return UNKNOWN_OUT if amount < 0 else UNKNOWN_IN


def add_rule(path: Path, pattern: str, account: str) -> str:
    """Append one rule to the table. Return the text for the owner."""
    if "|" in pattern or "\n" in pattern:
        raise RuleError("A pattern cannot contain '|' or a new line. Use two rules.")
    try:
        re.compile(pattern, re.IGNORECASE)
    except re.error as error:
        raise RuleError(f"The pattern is not a valid regular expression: {error}") from error
    _check_account(account)
    text = path.read_text(encoding="utf-8")
    if not text.endswith("\n"):
        text += "\n"
    path.write_text(text + f"| {pattern} | {account} |\n", encoding="utf-8")
    return f"Added the rule {pattern!r} -> {account}."


def _check_account(account: str) -> str:
    if not ACCOUNT.match(account):
        raise RuleError(
            f"{account!r} is not a valid account. Use lower case, for example expenses:food:groceries."
        )
    return account
