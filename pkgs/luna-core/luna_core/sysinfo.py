"""Tell the owner when the nixpkgs on luna is old."""

from __future__ import annotations

import re
from datetime import date
from pathlib import Path

VERSION_FILE = Path("/run/current-system/nixos-version")
MAX_AGE_DAYS = 14
_DATE = re.compile(r"\.(\d{4})(\d{2})(\d{2})\.")


def nixpkgs_date(version: str) -> date | None:
    match = _DATE.search(version)
    if match is None:
        return None
    return date(int(match[1]), int(match[2]), int(match[3]))


def update_notice(today: date, version: str | None = None) -> str | None:
    """Return a warning when nixpkgs is older than MAX_AGE_DAYS, or None."""
    if version is None:
        try:
            version = VERSION_FILE.read_text(encoding="utf-8").strip()
        except OSError:
            return "System notice: LUNA cannot read the NixOS version."
    built = nixpkgs_date(version)
    if built is None:
        return f"System notice: LUNA cannot read a date in the NixOS version {version!r}."
    age = (today - built).days
    if age <= MAX_AGE_DAYS:
        return None
    return (
        f"**System notice:** luna runs nixpkgs from {built.isoformat()}, {age} days ago. "
        "Security fixes are waiting. In nyx, run `nix flake update`, then `make deploy` in luna/."
    )
