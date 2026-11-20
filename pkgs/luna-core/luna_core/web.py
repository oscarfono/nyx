"""The core API: chat, approvals, money and system, on a unix socket.

The Phoenix app is the only client. Refer to "Build: the core API" in LUNA.org.
"""

from __future__ import annotations

import base64
import binascii
import json
import subprocess
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from aiohttp import web

from .approvals import Approvals
from .audit import AuditLog
from .sysinfo import update_notice

IMAGE_TYPES = frozenset({"image/jpeg", "image/png", "image/webp"})
MAX_IMAGE_BYTES = 5 * 1024 * 1024


class WebApp:
    def __init__(self, agent: Any, approvals: Approvals, audit: AuditLog,
                 money: Any = None, settings: dict[str, Any] | None = None, memory_root: Any = None) -> None:
        self.agent = agent
        self.approvals = approvals
        self.audit = audit
        self.money = money
        self.settings = settings or {}
        self.memory_root = memory_root
        self.started = datetime.now(UTC)

    def app(self) -> web.Application:
        app = web.Application(client_max_size=8 * 1024 * 1024)
        app.add_routes([
            web.get("/api/history", self.history),
            web.post("/api/chat", self.chat),
            web.get("/api/approvals", self.list_approvals),
            web.post("/api/approvals/{id}/{action}", self.decide),
            web.get("/api/money", self.money_panel),
            web.get("/api/system", self.system),
        ])
        return app

    async def history(self, _: web.Request) -> web.Response:
        return web.json_response({"messages": self.agent.transcript()})

    async def chat(self, request: web.Request) -> web.Response:
        body = await request.json()
        text = str(body.get("text", "")).strip()
        image = body.get("image")
        images: list[tuple[str, str]] = []
        if image:
            media_type = str(image.get("media_type", ""))
            data = str(image.get("data", ""))
            if media_type not in IMAGE_TYPES:
                return web.json_response({"error": "LUNA accepts JPEG, PNG or WebP images."}, status=400)
            try:
                size = len(base64.b64decode(data, validate=True))
            except (binascii.Error, ValueError):
                return web.json_response({"error": "The image data is not valid base64."}, status=400)
            if size > MAX_IMAGE_BYTES:
                return web.json_response({"error": "The image is more than 5 MB."}, status=400)
            images.append((media_type, data))
        if not text and not images:
            return web.json_response({"error": "Write a message."}, status=400)
        self.audit.write("web.chat", chars=len(text), images=len(images))
        reply = await self.agent.ask(text or "What do you see?", images=images)
        return web.json_response({"reply": reply})

    async def list_approvals(self, _: web.Request) -> web.Response:
        items = [{"id": i.id, "summary": i.summary, "created": i.created} for i in self.approvals.pending()]
        return web.json_response({"approvals": items})

    async def decide(self, request: web.Request) -> web.Response:
        request_id, action = request.match_info["id"], request.match_info["action"]
        if action == "approve":
            result = await self.approvals.approve(request_id)
        elif action == "deny":
            result = self.approvals.deny(request_id)
        else:
            return web.json_response({"error": "Use approve or deny."}, status=400)
        self.audit.write("web.decision", id=request_id, action=action)
        return web.json_response({"result": result})

    async def money_panel(self, _: web.Request) -> web.Response:
        if self.money is None:
            return web.json_response({"text": "Money is off. Refer to 'The gate for phase 2' in LUNA.org."})
        return web.json_response({"text": self.money.summary()})

    async def system(self, _: web.Request) -> web.Response:
        today = datetime.now(UTC).date()
        last_commit = ""
        if self.memory_root is not None:
            result = subprocess.run(["git", "-C", str(self.memory_root), "log", "-1", "--format=%h %s (%cr)"],
                                    capture_output=True, text=True, check=False)
            last_commit = result.stdout.strip()
        events = []
        try:
            lines = self.audit.path.read_text(encoding="utf-8").splitlines()[-15:]
        except OSError:
            lines = []
        for line in lines:
            record = json.loads(line)
            events.append({"time": record.get("time", ""), "event": record.get("event", "")})
        return web.json_response({
            "started": self.started.isoformat(),
            "update": update_notice(today) or "nixpkgs is less than 14 days old.",
            "memory": last_commit,
            "settings": self.settings,
            "pending_approvals": len(self.approvals.pending()),
            "events": events,
        })


async def serve(webapp: WebApp, path: Path) -> None:
    """Run the core API on the unix socket at path until the process stops."""
    runner = web.AppRunner(webapp.app(), access_log=None)
    await runner.setup()
    # A socket from an earlier run stops the bind.
    path.unlink(missing_ok=True)
    site = web.UnixSite(runner, str(path))
    await site.start()
    webapp.audit.write("api.ready", path=str(path))
