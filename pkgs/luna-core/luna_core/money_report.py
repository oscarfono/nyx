"""Run fixed hledger reports, and return totals."""

from __future__ import annotations

import csv
import io
import re
import shutil
import subprocess
from collections import defaultdict
from datetime import date, timedelta
from decimal import Decimal
from pathlib import Path

_AMOUNT = re.compile(r"^(?:(?P<pre>[A-Z]{3})\s*)?(?P<num>-?[\d,]*\.?\d+)(?:\s*(?P<post>[A-Z]{3}))?$")


class ReportError(Exception):
    """hledger failed."""


def hledger(main: Path, *args: str) -> str:
    binary = shutil.which("hledger")
    if binary is None:
        raise ReportError("hledger is not on the PATH.")
    result = subprocess.run([binary, "-f", str(main), *args], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise ReportError(result.stderr.strip() or "hledger failed")
    return result.stdout


def parse_amounts(cell: str) -> dict[str, Decimal]:
    totals: dict[str, Decimal] = defaultdict(Decimal)
    for part in cell.split(","):
        part = part.strip()
        if not part or part == "0":
            continue
        match = _AMOUNT.match(part)
        if match is None:
            continue
        currency = match["pre"] or match["post"] or "?"
        totals[currency] += Decimal(match["num"].replace(",", ""))
    return dict(totals)


def balances(main: Path, query: list[str], begin: date | None = None, end: date | None = None) -> dict[str, dict[str, Decimal]]:
    args = ["balance", *query, "--flat", "--no-total", "--layout=bare", "-O", "csv"]
    if begin is not None:
        args += ["-b", begin.isoformat()]
    if end is not None:
        args += ["-e", end.isoformat()]
    rows = list(csv.reader(io.StringIO(hledger(main, *args))))
    out: dict[str, dict[str, Decimal]] = defaultdict(lambda: defaultdict(Decimal))
    for row in rows[1:]:
        if len(row) < 3:
            continue
        account, commodity, amount = row[0], row[1], row[2]
        for currency, value in parse_amounts(f"{commodity} {amount}".strip()).items():
            out[account][currency] += value
    return {account: dict(values) for account, values in out.items()}


def total(by_account: dict[str, dict[str, Decimal]]) -> dict[str, Decimal]:
    out: dict[str, Decimal] = defaultdict(Decimal)
    for values in by_account.values():
        for currency, value in values.items():
            out[currency] += value
    return dict(out)


def money_text(values: dict[str, Decimal]) -> str:
    shown = [f"{currency} {value:,.2f}" for currency, value in sorted(values.items()) if value != 0]
    return ", ".join(shown) or "0"


def week_window(today: date) -> tuple[date, date]:
    """The last 7 days, today included. The end date is exclusive."""
    return today - timedelta(days=6), today + timedelta(days=1)
