"""Start LUNA."""

from __future__ import annotations

import asyncio
from datetime import datetime, time
from zoneinfo import ZoneInfo

from . import config as config_module
from .agent import Agent
from .approvals import Approvals
from .audit import AuditLog
from .matrix_bot import Bot
from .memory import Memory
from .money import Money
from .money_tools import build_money_tools
from .scheduler import brief_loop, sync_loop
from .telegram import Nudger
from .tools import build_tools


async def run() -> None:
    config = config_module.load()
    audit = AuditLog(config.audit_file)
    memory = Memory(config.memory_dir, audit)
    approvals = Approvals(config.approvals_dir, audit)
    nudger = Nudger(config.telegram_token, config.telegram_chat_id, audit)

    money: Money | None = None

    def make_agent() -> Agent:
        agent = Agent(config, [], audit)
        agent.tools = build_tools(memory, audit, agent.now, agent.taint)
        if money is not None:
            agent.tools += build_money_tools(money, audit, agent.taint)
        return agent

    if config.money_enabled:
        zone = ZoneInfo(config.owner_timezone)
        money = Money(memory, config.inbox_dir, audit, lambda: datetime.now(zone).date())
    chat_agent = make_agent()
    bot = Bot(config, chat_agent, approvals, nudger, audit)
    hour, minute = (int(part) for part in config.brief_time.split(":"))
    audit.write("luna.start", model=config.model)
    await asyncio.gather(
        bot.run(),
        brief_loop(make_agent, bot, audit, time(hour, minute), money),
        sync_loop(memory, audit),
    )


def main() -> None:
    asyncio.run(run())
