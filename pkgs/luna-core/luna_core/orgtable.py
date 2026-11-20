"""Read the tables in an org-mode file, by the heading above each table."""

from __future__ import annotations

import re

_HEADING = re.compile(r"^\*+\s+(.*?)\s*$")


def tables_by_heading(text: str) -> dict[str, list[list[str]]]:
    """Return the rows of each table under its nearest heading. Rules are omitted."""
    tables: dict[str, list[list[str]]] = {}
    heading: str | None = None
    for line in text.splitlines():
        match = _HEADING.match(line)
        if match:
            heading = match.group(1)
            continue
        cells = line.strip()
        if heading is None or not cells.startswith("|") or cells.startswith("|-"):
            continue
        tables.setdefault(heading, []).append([cell.strip() for cell in cells.strip("|").split("|")])
    return tables


def records(rows: list[list[str]]) -> list[dict[str, str]]:
    """Use the first row as the column names."""
    if not rows:
        return []
    names = rows[0]
    return [dict(zip(names, row, strict=False)) for row in rows[1:]]
