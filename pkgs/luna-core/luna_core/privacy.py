"""Classify memory paths, track the taint of a conversation, and mask numbers."""

from __future__ import annotations

import posixpath
import re

# Paths that hold money data, or text that LUNA made from money data.
SENSITIVE_FILES = frozenset({"money.org"})
SENSITIVE_DIRS = ("money/", "briefs/")

# Tools that send data out of LUNA. A tainted conversation cannot use them.
OUTBOUND_TOOLS = ("web_search", "web_fetch")


def is_sensitive(path: str) -> bool:
    clean = posixpath.normpath(path).lstrip("/")
    return clean in SENSITIVE_FILES or clean.startswith(SENSITIVE_DIRS)


class Taint:
    """Record that a conversation read money data. A new conversation is clean."""

    def __init__(self) -> None:
        self.reason: str | None = None

    @property
    def active(self) -> bool:
        return self.reason is not None

    def mark(self, reason: str) -> None:
        if self.reason is None:
            self.reason = reason

    def clear(self) -> None:
        self.reason = None


def write_refusal(taint: Taint, path: str) -> str | None:
    """Return the refusal text when a tainted conversation writes a clean path."""
    if taint.active and not is_sensitive(path):
        return (
            "Error: this conversation read money data. LUNA can write to "
            "money.org, money/ or briefs/ only. Start a new conversation with /new."
        )
    return None


# A run of digits with single spaces or dashes between groups. A letter can
# touch the run ("xx4111 1111 ..."), and the mask still applies. A decimal
# point or a comma next to the run means an amount, so the mask skips it.
_DIGIT_RUN = re.compile(r"(?<![\d.,])\d(?:[ -]?\d)*(?![\d]|[.,]\d)")


def mask_numbers(text: str, min_digits: int = 6) -> str:
    """Mask account and card numbers. Keep the last four digits.

    Use this on description text only. Do not use it on an amount column.
    """

    def mask(match: re.Match[str]) -> str:
        digits = re.sub(r"\D", "", match.group(0))
        if len(digits) < min_digits:
            return match.group(0)
        return "*" * (len(digits) - 4) + digits[-4:]

    return _DIGIT_RUN.sub(mask, text)
