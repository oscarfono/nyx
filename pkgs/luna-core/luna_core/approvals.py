"""Hold tier 2 actions until the owner approves them.

A tier 2 tool calls Approvals.request(). The request goes to disk.
Only the bot calls approve() or deny(), when the owner sends a command.
The model has no path to approve() or deny().
"""

from __future__ import annotations

import json
import secrets
from collections.abc import Awaitable, Callable
from dataclasses import asdict, dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from .audit import AuditLog

Executor = Callable[[dict[str, Any]], Awaitable[str]]
Notifier = Callable[["Request"], Awaitable[None]]


@dataclass
class Request:
    id: str
    action: str
    params: dict[str, Any]
    summary: str
    created: str

    def expired(self, ttl: timedelta, now: datetime | None = None) -> bool:
        now = now or datetime.now(UTC)
        return now - datetime.fromisoformat(self.created) > ttl


class Approvals:
    def __init__(self, directory: Path, audit: AuditLog, ttl: timedelta = timedelta(hours=24)) -> None:
        self.directory = directory
        self.audit = audit
        self.ttl = ttl
        self.executors: dict[str, Executor] = {}
        self.notifiers: list[Notifier] = []

    def register(self, action: str, executor: Executor) -> None:
        self.executors[action] = executor

    def _path(self, request_id: str) -> Path:
        if not request_id.isalnum():
            raise ValueError("The request ID is not valid.")
        return self.directory / f"{request_id}.json"

    async def request(self, action: str, params: dict[str, Any], summary: str) -> Request:
        if action not in self.executors:
            raise ValueError(f"No executor for the action {action}.")
        item = Request(
            id=secrets.token_hex(3),
            action=action,
            params=params,
            summary=summary,
            created=datetime.now(UTC).isoformat(),
        )
        self._path(item.id).write_text(json.dumps(asdict(item)), encoding="utf-8")
        self.audit.write("approval.requested", id=item.id, action=action, params=params)
        for notify in self.notifiers:
            await notify(item)
        return item

    def get(self, request_id: str) -> Request | None:
        try:
            path = self._path(request_id)
        except ValueError:
            return None
        if not path.exists():
            return None
        return Request(**json.loads(path.read_text(encoding="utf-8")))

    def pending(self) -> list[Request]:
        items = [Request(**json.loads(p.read_text(encoding="utf-8"))) for p in self.directory.glob("*.json")]
        return sorted(items, key=lambda item: item.created)

    async def approve(self, request_id: str) -> str:
        item = self.get(request_id)
        if item is None:
            return f"There is no request {request_id}."
        self._path(item.id).unlink()
        if item.expired(self.ttl):
            self.audit.write("approval.expired", id=item.id, action=item.action)
            return f"The request {item.id} expired. Ask LUNA again."
        self.audit.write("approval.approved", id=item.id, action=item.action)
        try:
            result = await self.executors[item.action](item.params)
        except Exception as error:  # noqa: BLE001 - the owner must see each failure
            self.audit.write("approval.failed", id=item.id, action=item.action, error=repr(error))
            return f"The action {item.action} failed: {error}"
        self.audit.write("approval.done", id=item.id, action=item.action, result=result)
        return result

    def deny(self, request_id: str) -> str:
        item = self.get(request_id)
        if item is None:
            return f"There is no request {request_id}."
        self._path(item.id).unlink()
        self.audit.write("approval.denied", id=item.id, action=item.action)
        return f"Denied: {item.summary}"
