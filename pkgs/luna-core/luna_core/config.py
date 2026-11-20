"""Read the LUNA configuration from the environment and from systemd credentials."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _credential(name: str) -> str | None:
    """Return a secret from $CREDENTIALS_DIRECTORY, or from an environment variable."""
    directory = os.environ.get("CREDENTIALS_DIRECTORY")
    if directory:
        path = Path(directory) / name
        if path.exists():
            return path.read_text(encoding="utf-8").strip()
    return os.environ.get(f"LUNA_{name.upper()}")


def _required(value: str | None, name: str) -> str:
    if not value:
        raise SystemExit(f"LUNA: the setting {name} is missing.")
    return value


@dataclass(frozen=True)
class Config:
    state_dir: Path
    homeserver: str
    matrix_user: str
    owner: str
    owner_timezone: str
    brief_time: str
    model: str
    effort: str
    anthropic_api_key: str
    matrix_password: str
    telegram_token: str | None
    telegram_chat_id: str | None
    money_enabled: bool = False
    owner_login: str = ""
    web_origin: str = ""
    web_port: int = 8090
    wise_json: str = '{"mode": "off"}'
    wise_token: str | None = None

    @property
    def inbox_dir(self) -> Path:
        return self.state_dir / "inbox"

    @property
    def memory_dir(self) -> Path:
        return self.state_dir / "memory"

    @property
    def approvals_dir(self) -> Path:
        return self.state_dir / "approvals"

    @property
    def audit_file(self) -> Path:
        return self.state_dir / "audit" / "audit.jsonl"


def load() -> Config:
    env = os.environ.get
    return Config(
        state_dir=Path(env("LUNA_STATE_DIR", "/var/lib/luna")),
        homeserver=_required(env("LUNA_HOMESERVER"), "LUNA_HOMESERVER"),
        matrix_user=_required(env("LUNA_MATRIX_USER"), "LUNA_MATRIX_USER"),
        owner=_required(env("LUNA_OWNER"), "LUNA_OWNER"),
        owner_timezone=env("LUNA_OWNER_TIMEZONE", "UTC"),
        brief_time=env("LUNA_BRIEF_TIME", "07:00"),
        model=env("LUNA_MODEL", "claude-opus-5-5"),
        effort=env("LUNA_EFFORT", "medium"),
        anthropic_api_key=_required(_credential("anthropic_api_key"), "anthropic_api_key"),
        matrix_password=_required(_credential("matrix_password"), "matrix_password"),
        telegram_token=_credential("telegram_token"),
        telegram_chat_id=_credential("telegram_chat_id"),
        money_enabled=env("LUNA_MONEY", "0") == "1",
        owner_login=env("LUNA_OWNER_LOGIN", ""),
        web_origin=env("LUNA_WEB_ORIGIN", ""),
        web_port=int(env("LUNA_WEB_PORT", "8090")),
        wise_json=env("LUNA_WISE", '{"mode": "off"}'),
        wise_token=_credential("wise_api_token"),
    )
