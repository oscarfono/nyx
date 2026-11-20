"""Import bank files, and give the agent totals. Code does all arithmetic."""

from __future__ import annotations

import csv
import io
from collections.abc import Callable
from datetime import date, timedelta
from pathlib import Path

from .audit import AuditLog
from .memory import Memory, MemoryAccessError
from .money_import import MoneyFileError, account_for, entry, existing_ids, read_file
from .money_plan import load_plan
from .money_report import ReportError, balances, hledger, money_text, total, week_window
from .money_rules import RuleError, add_rule, load_rules


class Money:
    def __init__(self, memory: Memory, inbox: Path, audit: AuditLog, today: Callable[[], date]) -> None:
        self.memory = memory
        self.inbox = inbox
        self.audit = audit
        self.today = today

    @property
    def root(self) -> Path:
        return self.memory.root / "money"

    @property
    def main(self) -> Path:
        return self.root / "main.journal"

    def _main_problem(self) -> str | None:
        """An old main.journal does not include the files that the import writes."""
        if not self.main.exists():
            return "money/main.journal does not exist."
        if "include tx/*.journal" not in self.main.read_text(encoding="utf-8"):
            return ("money/main.journal has no line 'include tx/*.journal', so hledger cannot see "
                    "the imported transactions. Add the line, or copy the seed main.journal.")
        return None

    def import_inbox(self) -> str:
        """Import each CSV file in the inbox. Return counts, not transactions."""
        self.memory.sync()
        problem = self._main_problem()
        if problem is not None:
            return f"No import: {problem}"
        files = sorted(self.inbox.glob("*.csv")) + sorted(self.inbox.glob("*.CSV"))
        if not files:
            return "The inbox is empty. Send files with make money-upload."
        rules, problems = load_rules(self.root / "categories.org")
        tx_dir = self.root / "tx"
        tx_dir.mkdir(exist_ok=True)
        known = existing_ids(tx_dir)
        lines: list[str] = []
        done: list[Path] = []
        changed: set[str] = set()
        for path in files:
            try:
                profile, account, transactions = read_file(path)
            except MoneyFileError as error:
                lines.append(f"- Kept {path.name}: {error}")
                self.audit.write("money.import_refused", file=path.name, error=str(error))
                continue
            ledger_account = account_for(profile.name, account)
            new = [t for t in transactions if t.luna_id not in known]
            by_year: dict[int, list[str]] = {}
            unknown = 0
            for txn in sorted(new, key=lambda t: t.day):
                text = entry(txn, ledger_account, rules)
                unknown += ":unknown  " in text
                by_year.setdefault(txn.day.year, []).append(text)
                known.add(txn.luna_id)
            for year, entries in by_year.items():
                journal = tx_dir / f"{year}.journal"
                with journal.open("a", encoding="utf-8") as handle:
                    handle.writelines(entries)
                changed.add(str(journal.relative_to(self.memory.root)))
            lines.append(
                f"- {path.name}: {len(new)} new, {len(transactions) - len(new)} already imported, "
                f"{unknown} with no category"
            )
            self.audit.write("money.imported", file=path.name, new=len(new), unknown=unknown)
            done.append(path)
        if changed:
            try:
                self.memory.commit(sorted(changed), f"LUNA: import {len(done)} bank file(s)")
            except MemoryAccessError as error:
                return f"The import wrote the journal, but the commit failed: {error}. The files stay in the inbox."
        for path in done:
            path.unlink()
        if problems:
            lines.append("Rules with problems: " + "; ".join(problems))
        return "Import:\n" + "\n".join(lines)

    def summary(self) -> str:
        """Balances, the spend of the last 7 days, and the safe-to-spend number."""
        problem = self._main_problem()
        if problem is not None:
            return f"No summary: {problem}"
        today = self.today()
        try:
            held = balances(self.main, ["^assets", "^liabilities"], end=today + timedelta(days=1))
            begin, end = week_window(today)
            spent = total(balances(self.main, ["^expenses"], begin, end))
            unknown = balances(self.main, ["^expenses:unknown", "^income:unknown"], today - timedelta(days=30), end)
        except ReportError as error:
            return f"hledger failed: {error}"
        plan = load_plan(self.memory.root / "money.org")
        lines = ["**Money**", "", "| Account | Balance |", "|---|---|"]
        lines += [f"| {account} | {money_text(values)} |" for account, values in sorted(held.items())
                  if any(v != 0 for v in values.values())]
        lines += ["", f"Spent in the last 7 days: {money_text(spent)}"]
        weekly = plan.spend_per_week
        if weekly is None:
            lines.append("Safe to spend per week: not known. " + "; ".join(plan.missing))
        else:
            spent_aud = spent.get("AUD")
            left = weekly - spent_aud if spent_aud is not None else weekly
            lines.append(f"Safe to spend per week: AUD {weekly:,.2f}. Left this week: AUD {left:,.2f}")
        if unknown:
            lines.append(f"Transactions with no category in 30 days: {money_text(total(unknown))}. Ask LUNA to show them.")
        return "\n".join(lines)

    def unknown(self, limit: int = 20) -> str:
        """The transactions with no category. The descriptions are masked."""
        today = self.today()
        try:
            out = hledger(self.main, "register", "^expenses:unknown", "^income:unknown",
                          "-b", (today - timedelta(days=90)).isoformat(), "-O", "csv")
        except ReportError as error:
            return f"hledger failed: {error}"
        rows = list(csv.DictReader(io.StringIO(out)))[-limit:]
        if not rows:
            return "Each transaction has a category."
        return "\n".join(f"- {r['date']} {r['description']}: {r['amount']}" for r in rows)

    def add_rule(self, pattern: str, account: str) -> str:
        self.memory.sync()
        path = self.root / "categories.org"
        try:
            text = add_rule(path, pattern, account)
            self.memory.commit([str(path.relative_to(self.memory.root))], f"LUNA: add the rule {pattern}")
        except (RuleError, MemoryAccessError) as error:
            return f"Error: {error}"
        self.audit.write("money.rule_added", pattern=pattern, account=account)
        return text + " The rule applies to the next import."
