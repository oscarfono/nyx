"""The LUNA web app: chat, approvals, money and system. Tailnet only."""

from __future__ import annotations

import base64
import binascii
import json
import subprocess
from datetime import UTC, datetime
from typing import Any

from aiohttp import web

from .approvals import Approvals
from .audit import AuditLog
from .sysinfo import update_notice
from .web_page import APP_CSS, APP_JS, INDEX_HTML

LOGIN_HEADER = "Tailscale-User-Login"
IMAGE_TYPES = frozenset({"image/jpeg", "image/png", "image/webp"})
MAX_IMAGE_BYTES = 5 * 1024 * 1024
CSP = (
    "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data: blob:; "
    "media-src 'self' blob:; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
)


class WebApp:
    def __init__(self, agent: Any, approvals: Approvals, audit: AuditLog, owner_login: str, origin: str,
                 money: Any = None, settings: dict[str, Any] | None = None, memory_root: Any = None) -> None:
        self.agent = agent
        self.approvals = approvals
        self.audit = audit
        self.owner_login = owner_login
        self.origin = origin
        self.money = money
        self.settings = settings or {}
        self.memory_root = memory_root
        self.started = datetime.now(UTC)

    def app(self) -> web.Application:
        app = web.Application(middlewares=[self.guard], client_max_size=8 * 1024 * 1024)
        app.add_routes([
            web.get("/", self.index),
            web.get("/app.js", self.script),
            web.get("/app.css", self.style),
            web.get("/api/history", self.history),
            web.post("/api/chat", self.chat),
            web.get("/api/approvals", self.list_approvals),
            web.post("/api/approvals/{id}/{action}", self.decide),
            web.get("/api/money", self.money_panel),
            web.get("/api/system", self.system),
        ])
        return app

    @web.middleware
    async def guard(self, request: web.Request, handler: Any) -> web.StreamResponse:
        login = request.headers.get(LOGIN_HEADER)
        if login != self.owner_login:
            self.audit.write("web.refused", reason="login", path=request.path)
            return web.Response(status=403, text="LUNA: this page is for the owner only.")
        if request.method != "GET":
            if request.headers.get("Origin") != self.origin or request.headers.get("X-Luna") != "1":
                self.audit.write("web.refused", reason="origin", path=request.path)
                return web.Response(status=403, text="LUNA: the request has no valid origin.")
        response = await handler(request)
        response.headers["Content-Security-Policy"] = CSP
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Cache-Control"] = "no-store"
        return response

    async def index(self, _: web.Request) -> web.Response:
        return web.Response(text=INDEX_HTML, content_type="text/html")

    async def script(self, _: web.Request) -> web.Response:
        return web.Response(text=APP_JS, content_type="application/javascript")

    async def style(self, _: web.Request) -> web.Response:
        return web.Response(text=APP_CSS, content_type="text/css")

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


async def serve(webapp: WebApp, port: int) -> None:
    """Run the web app on 127.0.0.1 until the process stops."""
    runner = web.AppRunner(webapp.app(), access_log=None)
    await runner.setup()
    site = web.TCPSite(runner, "127.0.0.1", port)
    await site.start()
    webapp.audit.write("web.ready", port=port)
