"""The tools that the agent can use, by tier."""

from __future__ import annotations

from collections.abc import Callable
from datetime import datetime
from typing import Any

from anthropic import beta_async_tool

from .audit import AuditLog
from .memory import Memory, MemoryAccessError
from .privacy import Taint, is_sensitive, write_refusal

# Server tools run at Anthropic. Their results are untrusted text (tier 0).
# Both tools also send data out, so a tainted conversation loses them.
SERVER_TOOLS: list[dict[str, Any]] = [
    {"type": "web_search_20260209", "name": "web_search", "max_uses": 5},
    {"type": "web_fetch_20260209", "name": "web_fetch", "max_uses": 5},
]


def build_tools(memory: Memory, audit: AuditLog, now: Callable[[], datetime], taint: Taint) -> list[Any]:
    @beta_async_tool
    async def memory_files() -> str:
        """List the files in the LUNA memory."""
        audit.write("tool", name="memory_files")
        return "\n".join(memory.files()) or "The memory is empty."

    @beta_async_tool
    async def memory_search(query: str) -> str:
        """Search the LUNA memory for a text. The search ignores case.

        Args:
            query: The text to find.
        """
        audit.write("tool", name="memory_search", query=query)
        try:
            hits = memory.search(query)
        except MemoryAccessError as error:
            return f"Error: {error}"
        if any(is_sensitive(hit.split(":", 1)[0]) for hit in hits):
            taint.mark("memory_search found money data")
        return "\n".join(hits) or "No match."

    @beta_async_tool
    async def memory_read(path: str) -> str:
        """Read one file from the LUNA memory.

        Args:
            path: The path relative to the memory root, for example "money.org".
        """
        audit.write("tool", name="memory_read", path=path)
        try:
            text = memory.read(path)
        except MemoryAccessError as error:
            return f"Error: {error}"
        if is_sensitive(path):
            taint.mark(f"memory_read {path}")
        return text

    @beta_async_tool
    async def memory_append(path: str, heading: str, body: str) -> str:
        """Add one org-mode entry to the end of a memory file. Git records each change.

        Args:
            path: The path relative to the memory root. The file can be new.
            heading: The heading of the entry, on one line.
            body: The body of the entry, in org-mode text.
        """
        audit.write("tool", name="memory_append", path=path, heading=heading)
        refusal = write_refusal(taint, path)
        if refusal is not None:
            audit.write("tool.refused", name="memory_append", path=path, reason="taint")
            return refusal
        try:
            return memory.append(path, heading, body, now())
        except MemoryAccessError as error:
            return f"Error: {error}"

    return [memory_files, memory_search, memory_read, memory_append, *SERVER_TOOLS]
