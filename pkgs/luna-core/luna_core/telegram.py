"""Send a short nudge to Telegram. A nudge contains no personal data."""

from __future__ import annotations

import httpx

from .audit import AuditLog


class Nudger:
    def __init__(self, token: str | None, chat_id: str | None, audit: AuditLog) -> None:
        self.token = token
        self.chat_id = chat_id
        self.audit = audit

    @property
    def enabled(self) -> bool:
        return bool(self.token and self.chat_id)

    async def nudge(self, text: str) -> None:
        if not self.enabled:
            return
        url = f"https://api.telegram.org/bot{self.token}/sendMessage"
        try:
            async with httpx.AsyncClient(timeout=15) as client:
                response = await client.post(url, json={"chat_id": self.chat_id, "text": text})
                response.raise_for_status()
        except httpx.HTTPError as error:
            self.audit.write("telegram.error", error=type(error).__name__)
