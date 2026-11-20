"""Run the scheduled jobs: the morning brief and the memory sync."""

from __future__ import annotations

import asyncio
from collections.abc import Callable
from datetime import datetime, time, timedelta

from .agent import Agent
from .audit import AuditLog
from .matrix_bot import Bot
from .memory import Memory, MemoryAccessError
from .sysinfo import update_notice

BRIEF_PROMPT = """\
Write the morning brief for today. First read roster.org, money.org,
projects.org and travel.org. Then give, in this order and in less than 200 words:
1. Where Coops is in the roster, and the days to the next change.
2. Money: the safe-to-spend number and any cost due in the next 14 days.
3. The SHIP project: one next step for today.
4. One action for the next off-swing, if the next off-swing is in 30 days or less.
If a file has no data yet, say which data you need. Write the brief to
briefs/<YYYY>.org with the heading "Brief <YYYY-MM-DD>".
"""


def next_run(now: datetime, at: time) -> datetime:
    candidate = now.replace(hour=at.hour, minute=at.minute, second=0, microsecond=0)
    if candidate <= now:
        candidate += timedelta(days=1)
    return candidate


async def brief_loop(make_agent: Callable[[], Agent], bot: Bot, audit: AuditLog, at: time) -> None:
    while True:
        agent = make_agent()
        now = agent.now()
        await asyncio.sleep((next_run(now, at) - now).total_seconds())
        try:
            text = await agent.ask(BRIEF_PROMPT)
            notice = update_notice(agent.now().date())
            if notice is not None:
                text = f"{notice}\n\n{text}"
            await bot.send_owner(text)
            audit.write("brief.sent")
        except Exception as error:  # noqa: BLE001 - the loop must not stop
            audit.write("brief.error", error=repr(error))
        await asyncio.sleep(60)


async def sync_loop(memory: Memory, audit: AuditLog, every: timedelta = timedelta(minutes=5)) -> None:
    while True:
        await asyncio.sleep(every.total_seconds())
        try:
            await asyncio.to_thread(memory.sync)
        except MemoryAccessError as error:
            audit.write("memory.sync_error", error=str(error))
