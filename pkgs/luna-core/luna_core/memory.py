"""Read, search and append to the org-mode memory in git."""

from __future__ import annotations

import subprocess
from datetime import datetime
from pathlib import Path

from .audit import AuditLog

ALLOWED_SUFFIXES = {".org", ".journal"}
MAX_READ_CHARS = 200_000


class MemoryAccessError(Exception):
    """The memory operation is not permitted or failed."""


class Memory:
    def __init__(self, root: Path, audit: AuditLog, remote: bool = True) -> None:
        self.root = root.resolve()
        self.audit = audit
        self.remote = remote

    def _git(self, *args: str) -> str:
        result = subprocess.run(
            ["git", "-C", str(self.root), *args],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise MemoryAccessError(f"git {args[0]} failed: {result.stderr.strip()}")
        return result.stdout

    def sync(self) -> None:
        if self.remote:
            self._git("pull", "--rebase", "--quiet")

    def resolve(self, relative: str) -> Path:
        candidate = Path(relative)
        if candidate.is_absolute():
            raise MemoryAccessError("Use a path that is relative to the memory root.")
        path = (self.root / candidate).resolve()
        if not path.is_relative_to(self.root) or ".git" in path.relative_to(self.root).parts:
            raise MemoryAccessError("The path is outside the memory.")
        if path.suffix not in ALLOWED_SUFFIXES:
            raise MemoryAccessError("LUNA can open .org and .journal files only.")
        return path

    def files(self) -> list[str]:
        return sorted(
            str(p.relative_to(self.root))
            for p in self.root.rglob("*")
            if p.suffix in ALLOWED_SUFFIXES and ".git" not in p.parts
        )

    def read(self, relative: str) -> str:
        self.sync()
        path = self.resolve(relative)
        if not path.exists():
            raise MemoryAccessError(f"The file {relative} does not exist.")
        text = path.read_text(encoding="utf-8")
        if len(text) > MAX_READ_CHARS:
            return text[:MAX_READ_CHARS] + "\n[LUNA: the file is longer. The text stops here.]"
        return text

    def search(self, query: str, limit: int = 40) -> list[str]:
        self.sync()
        needle = query.casefold()
        hits: list[str] = []
        for relative in self.files():
            lines = (self.root / relative).read_text(encoding="utf-8").splitlines()
            for number, line in enumerate(lines, start=1):
                if needle in line.casefold():
                    hits.append(f"{relative}:{number}: {line.strip()}")
                    if len(hits) >= limit:
                        return hits
        return hits

    def commit(self, paths: list[str], message: str) -> None:
        """Commit the files at the paths, then push. Do nothing when no file changed."""
        self._git("add", "--", *paths)
        if not self._git("status", "--porcelain", "--", *paths).strip():
            return
        self._git("commit", "--quiet", "-m", message, "--", *paths)
        if self.remote:
            self._git("push", "--quiet", "origin", "HEAD:main")

    def append(self, relative: str, heading: str, body: str, now: datetime) -> str:
        self.sync()
        path = self.resolve(relative)
        path.parent.mkdir(parents=True, exist_ok=True)
        stamp = now.strftime("[%Y-%m-%d %a %H:%M]")
        title = heading.replace("\n", " ").strip()
        entry = f"\n* {title}\n:PROPERTIES:\n:CREATED: {stamp}\n:END:\n{body.rstrip()}\n"
        with path.open("a", encoding="utf-8") as handle:
            handle.write(entry)
        rel = str(path.relative_to(self.root))
        self._git("add", "--", rel)
        self._git("commit", "--quiet", "-m", f"LUNA: add '{title}' to {rel}")
        if self.remote:
            self._git("push", "--quiet", "origin", "HEAD:main")
        self.audit.write("memory.append", file=rel, heading=title)
        return f"Added '{title}' to {rel}."
