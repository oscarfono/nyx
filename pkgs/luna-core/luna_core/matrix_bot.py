"""The Matrix bot: the owner's interface to LUNA."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

import markdown
from nio import (
    AsyncClient,
    InviteMemberEvent,
    LoginResponse,
    MatrixRoom,
    MegolmEvent,
    RoomCreateResponse,
    RoomMessageText,
    RoomPreset,
    RoomVisibility,
)

from .agent import Agent
from .approvals import Approvals, Request
from .audit import AuditLog
from .config import Config
from .telegram import Nudger


class Bot:
    def __init__(self, config: Config, agent: Agent, approvals: Approvals, nudger: Nudger, audit: AuditLog) -> None:
        self.config = config
        self.agent = agent
        self.approvals = approvals
        self.nudger = nudger
        self.audit = audit
        self.session_file = config.state_dir / "matrix-session.json"
        self.room_file = config.state_dir / "owner-room"
        self.started_ms = int(time.time() * 1000)
        self.client = AsyncClient(config.homeserver, config.matrix_user, store_path=str(config.state_dir))
        approvals.notifiers.append(self._on_approval_request)

    @property
    def owner_room(self) -> str | None:
        if self.room_file.exists():
            return self.room_file.read_text(encoding="utf-8").strip() or None
        return None

    async def _login(self) -> None:
        if self.session_file.exists():
            session = json.loads(self.session_file.read_text(encoding="utf-8"))
            self.client.restore_login(session["user_id"], session["device_id"], session["access_token"])
            return
        response = await self.client.login(self.config.matrix_password, device_name="luna-core")
        if not isinstance(response, LoginResponse):
            raise SystemExit(f"LUNA: the Matrix login failed: {response}")
        session = {
            "user_id": response.user_id,
            "device_id": response.device_id,
            "access_token": response.access_token,
        }
        self.session_file.write_text(json.dumps(session), encoding="utf-8")
        os.chmod(self.session_file, 0o600)

    async def send(self, room_id: str, text: str) -> None:
        room = self.client.rooms.get(room_id)
        if room is not None and room.encrypted:
            # nio has no encryption support here, and room_send would fail.
            self.audit.write("matrix.send_refused_encrypted", room=room_id)
            return
        html = markdown.markdown(text, extensions=["fenced_code", "tables"])
        content = {
            "msgtype": "m.text",
            "body": text,
            "format": "org.matrix.custom.html",
            "formatted_body": html,
        }
        await self.client.room_send(room_id, "m.room.message", content)

    async def send_owner(self, text: str) -> bool:
        room = self.owner_room
        if room is None:
            return False
        await self.send(room, text)
        return True

    async def _on_approval_request(self, item: Request) -> None:
        await self.send_owner(
            f"**Approval needed** `{item.id}`\n\n{item.summary}\n\n"
            f"Reply `approve {item.id}` or `deny {item.id}`. The request expires in 24 hours."
        )
        await self.nudger.nudge("LUNA needs your approval. Open Matrix.")

    async def _ensure_owner_room(self) -> None:
        """Make the unencrypted owner room, if LUNA has no owner room yet."""
        room = self.owner_room
        if room is not None and room in self.client.rooms:
            return
        response = await self.client.room_create(
            visibility=RoomVisibility.private,
            name="LUNA",
            topic="Private chat with LUNA. This room is not end-to-end encrypted.",
            # ement.el needs a room ID with a server part. Version 12 has none.
            room_version="11",
            is_direct=True,
            preset=RoomPreset.trusted_private_chat,
            invite=[self.config.owner],
            federate=False,
        )
        if not isinstance(response, RoomCreateResponse):
            self.audit.write("matrix.room_create_failed", error=str(response))
            return
        self.room_file.write_text(response.room_id, encoding="utf-8")
        self.audit.write("matrix.room_created", room=response.room_id)

    async def _on_encrypted(self, room: MatrixRoom, event: MegolmEvent) -> None:
        if event.sender != self.config.owner or event.server_timestamp < self.started_ms:
            return
        self.audit.write("matrix.encrypted_ignored", room=room.room_id)
        await self.send_owner(
            "You wrote to me in an encrypted room. I cannot read encrypted messages. "
            "Write to me here, in this room."
        )

    async def _on_invite(self, room: MatrixRoom, event: InviteMemberEvent) -> None:
        if event.state_key != self.config.matrix_user or event.membership != "invite":
            return
        if event.sender != self.config.owner:
            self.audit.write("matrix.invite_ignored", sender=event.sender)
            return
        await self.client.join(room.room_id)
        self.audit.write("matrix.joined", room=room.room_id)

    async def _on_message(self, room: MatrixRoom, event: RoomMessageText) -> None:
        if event.sender == self.config.matrix_user or event.server_timestamp < self.started_ms:
            return
        if event.sender != self.config.owner:
            self.audit.write("matrix.message_ignored", sender=event.sender, room=room.room_id)
            return
        if self.owner_room != room.room_id:
            self.room_file.write_text(room.room_id, encoding="utf-8")

        text = event.body.strip()
        words = text.split()
        command = words[0].lower() if words else ""
        if command == "approve" and len(words) == 2:
            await self.send(room.room_id, await self.approvals.approve(words[1]))
            return
        if command == "deny" and len(words) == 2:
            await self.send(room.room_id, self.approvals.deny(words[1]))
            return
        if command == "pending" and len(words) == 1:
            items = self.approvals.pending()
            lines = [f"- `{item.id}` {item.summary}" for item in items]
            await self.send(room.room_id, "\n".join(lines) or "No held actions.")
            return
        if command == "/new":
            self.agent.reset()
            await self.send(room.room_id, "New conversation started.")
            return

        await self.client.room_typing(room.room_id, True, timeout=120_000)
        try:
            reply = await self.agent.ask(text)
        finally:
            await self.client.room_typing(room.room_id, False)
        await self.send(room.room_id, reply)

    async def run(self) -> None:
        await self._login()
        # The first sync skips the old events.
        await self.client.sync(timeout=0, full_state=True)
        for room_id, room in list(self.client.invited_rooms.items()):
            if getattr(room, "inviter", None) == self.config.owner:
                await self.client.join(room_id)
        self.client.add_event_callback(self._on_invite, InviteMemberEvent)
        self.client.add_event_callback(self._on_message, RoomMessageText)
        self.client.add_event_callback(self._on_encrypted, MegolmEvent)
        await self._ensure_owner_room()
        self.audit.write("matrix.ready", user=self.config.matrix_user)
        await self.client.sync_forever(timeout=30_000, full_state=True)
