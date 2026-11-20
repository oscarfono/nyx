"""Read bank CSV files, mask account numbers, and make hledger entries."""

from __future__ import annotations

import csv
import hashlib
import re
from collections import Counter
from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path

from .money_rules import Rule, categorise
from .privacy import mask_numbers

Column = str | int


class MoneyFileError(Exception):
    """The file does not agree with its profile."""


@dataclass(frozen=True)
class Profile:
    name: str
    currency: str
    date: Column
    amount: Column
    description: tuple[Column, ...]
    date_formats: tuple[str, ...]
    header: bool
    columns: int | None = None
    currency_column: Column | None = None
    id_column: Column | None = None
    verified: bool = False


PROFILES: dict[str, Profile] = {
    "commbank": Profile("commbank", "AUD", 0, 1, (2,), ("%d/%m/%Y",), header=False, columns=4),
    "bendigo": Profile("bendigo", "AUD", 0, 1, (2,), ("%d/%m/%Y",), header=False, columns=3),
    "up": Profile("up", "AUD", "Time", "Total (AUD)", ("Payee", "Description"), ("%Y-%m-%d",), header=True),
    "coopnz": Profile("coopnz", "NZD", "Date", "Amount", ("Details",), ("%d/%m/%Y",), header=True),
    "wise": Profile(
        "wise", "AUD", "Date", "Amount", ("Description", "Payee Name", "Merchant"),
        ("%d-%m-%Y", "%Y-%m-%d"), header=True, currency_column="Currency", id_column="TransferWise ID",
    ),
}

_NAME = re.compile(r"^(?P<profile>[a-z]+)--(?P<account>[a-z0-9-]+)\.csv$", re.IGNORECASE)
_ID_TAG = re.compile(r"luna-id:([0-9a-f]{16})")
_ISO_DAY = re.compile(r"^(\d{4}-\d{2}-\d{2})")


@dataclass(frozen=True)
class Transaction:
    day: date
    amount: Decimal
    currency: str
    description: str
    luna_id: str


def account_for(profile: str, account: str) -> str:
    return f"assets:bank:{profile}:{account.lower()}"


def profile_for(path: Path) -> tuple[Profile, str]:
    match = _NAME.match(path.name)
    if match is None:
        raise MoneyFileError(
            f"{path.name}: use the name <profile>--<account>.csv, for example commbank--personal.csv."
        )
    name = match["profile"].lower()
    if name not in PROFILES:
        raise MoneyFileError(f"{path.name}: no profile {name!r}. Profiles: {', '.join(PROFILES)}.")
    return PROFILES[name], match["account"].lower()


def parse_amount(text: str) -> Decimal:
    clean = text.strip()
    negative = clean.startswith("(") and clean.endswith(")")
    clean = re.sub(r"[\s$,()A-Za-z]", "", clean)
    try:
        value = Decimal(clean)
    except InvalidOperation as error:
        raise MoneyFileError(f"{text!r} is not an amount") from error
    return -value if negative else value


def parse_day(text: str, formats: tuple[str, ...]) -> date:
    clean = text.strip()
    iso = _ISO_DAY.match(clean)
    if iso:
        return date.fromisoformat(iso.group(1))
    for fmt in formats:
        try:
            return datetime.strptime(clean, fmt).date()
        except ValueError:
            continue
    raise MoneyFileError(f"{text!r} is not a date in the format {' or '.join(formats)}")


def clean_description(parts: list[str]) -> str:
    text = " ".join(part.strip() for part in parts if part and part.strip())
    # hledger reads ';' as the start of a comment, and '|' as payee|note.
    text = re.sub(r"[;|]", ",", text)
    text = re.sub(r"\s+", " ", text).strip()
    return mask_numbers(text) or "(no description)"


def read_file(path: Path) -> tuple[Profile, str, list[Transaction]]:
    profile, account = profile_for(path)
    with path.open(encoding="utf-8-sig", newline="") as handle:
        rows = [row for row in csv.reader(handle) if any(cell.strip() for cell in row)]
    if not rows:
        raise MoneyFileError(f"{path.name}: the file has no rows.")

    if profile.header:
        names = [cell.strip() for cell in rows[0]]
        wanted = [c for c in (profile.date, profile.amount, *profile.description,
                              profile.currency_column, profile.id_column) if isinstance(c, str)]
        missing = [c for c in wanted if c not in names]
        if missing:
            raise MoneyFileError(
                f"{path.name}: the header has no column {', '.join(missing)}. "
                f"The {profile.name} profile is unverified. Send LUNA the header row."
            )
        index = {name: i for i, name in enumerate(names)}
        body = rows[1:]
    else:
        index = {}
        body = rows
        wrong = [n for n, row in enumerate(body, 1) if len(row) != profile.columns]
        if wrong:
            raise MoneyFileError(
                f"{path.name}: row {wrong[0]} has {len(body[wrong[0] - 1])} columns. "
                f"The {profile.name} profile expects {profile.columns}."
            )

    def cell(row: list[str], column: Column | None) -> str:
        if column is None:
            return ""
        position = index[column] if isinstance(column, str) else column
        return row[position] if position < len(row) else ""

    seen: Counter[tuple[str, ...]] = Counter()
    transactions: list[Transaction] = []
    for number, row in enumerate(body, 1):
        try:
            day = parse_day(cell(row, profile.date), profile.date_formats)
            amount = parse_amount(cell(row, profile.amount))
        except MoneyFileError as error:
            raise MoneyFileError(f"{path.name}: data row {number}: {error}") from error
        currency = (cell(row, profile.currency_column).strip().upper() or profile.currency)
        raw = [cell(row, c) for c in profile.description]
        external = cell(row, profile.id_column).strip()
        if external:
            key: tuple[str, ...] = (profile.name, account, "id", external)
        else:
            base = (profile.name, account, day.isoformat(), str(amount), currency, " ".join(raw))
            seen[base] += 1
            key = (*base, str(seen[base]))
        luna_id = hashlib.sha256("\x1f".join(key).encode()).hexdigest()[:16]
        transactions.append(Transaction(day, amount, currency, clean_description(raw), luna_id))
    return profile, account, transactions


def existing_ids(tx_dir: Path) -> set[str]:
    ids: set[str] = set()
    for journal in tx_dir.glob("*.journal"):
        ids.update(_ID_TAG.findall(journal.read_text(encoding="utf-8")))
    return ids


def entry(txn: Transaction, account: str, rules: list[Rule]) -> str:
    category = categorise(txn.description, txn.amount, rules)
    amount = format(txn.amount, "f")
    opposite = format(-txn.amount, "f")
    return (
        f"{txn.day.isoformat()} {txn.description}  ; luna-id:{txn.luna_id}\n"
        f"    {category}  {txn.currency} {opposite}\n"
        f"    {account}  {txn.currency} {amount}\n\n"
    )
