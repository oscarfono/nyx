"""Read the plan in money.org, and calculate the safe-to-spend number."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation
from pathlib import Path

from .orgtable import records, tables_by_heading

WEEKS_PER_YEAR = Decimal(52)


@dataclass
class Plan:
    income: Decimal = Decimal(0)
    costs: Decimal = Decimal(0)
    buffer: Decimal = Decimal(0)
    invest: Decimal = Decimal(0)
    missing: list[str] = field(default_factory=list)

    @property
    def spend_per_week(self) -> Decimal | None:
        if self.income <= 0:
            return None
        return ((self.income - self.costs - self.buffer - self.invest) / WEEKS_PER_YEAR).quantize(Decimal("0.01"))


def number(text: str | None) -> Decimal | None:
    if text is None:
        return None
    clean = re.sub(r"[\s$,]|AUD", "", text)
    if not clean:
        return None
    try:
        return Decimal(clean)
    except InvalidOperation:
        return None


def load_plan(path: Path) -> Plan:
    tables = tables_by_heading(path.read_text(encoding="utf-8"))
    plan = Plan()

    for row in records(tables.get("Income", [])):
        per_year = number(row.get("Net per year"))
        if per_year is None:
            pay, pays = number(row.get("Net per pay (AUD)")), number(row.get("Pays per year"))
            per_year = pay * pays if pay is not None and pays is not None else None
        if per_year is not None:
            plan.income += per_year
    if plan.income <= 0:
        plan.missing.append("Income: write the net pay and the pays per year")

    costs = [number(row.get("Per year (AUD)")) for row in records(tables.get("Annual costs", []))]
    plan.costs = sum((c for c in costs if c is not None), Decimal(0))
    if not any(c is not None for c in costs):
        plan.missing.append("Annual costs: write the cost per year in each row")

    for row in records(tables.get("Targets", [])):
        value = number(row.get("Per year (AUD)"))
        target = row.get("Target", "").lower()
        if value is None:
            continue
        if target == "buffer":
            plan.buffer = value
        elif target == "invest":
            plan.invest = value
    return plan
