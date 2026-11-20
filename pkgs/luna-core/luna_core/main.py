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
from .payment_tools import build_payment_tools
from .payments import PaymentLog, Payments, WiseClient, WiseSettings
from .scheduler import brief_loop, payments_loop, sync_loop
from .telegram import Nudger
from .tools import build_tools
from .web import WebApp, serve


async def run() -> None:
    config = config_module.load()
    audit = AuditLog(config.audit_file)
    memory = Memory(config.memory_dir, audit)
    approvals = Approvals(config.approvals_dir, audit)
    nudger = Nudger(config.telegram_token, config.telegram_chat_id, audit)

    money: Money | None = None
    payment_tools: list = []
    wise = WiseSettings.from_json(config.wise_json)
    if wise.mode != "off":
        zone_p = ZoneInfo(config.owner_timezone)
        client = WiseClient(config.wise_token, wise.sandbox) if config.wise_token else None
        payments = Payments(wise, PaymentLog(config.state_dir / "payments.jsonl"), audit, client,
                            lambda: datetime.now(zone_p).date())
        payment_tools = build_payment_tools(payments, approvals, audit)
        audit.write("payments.ready", mode=wise.mode, sandbox=wise.sandbox, payees=sorted(wise.payees))

    def make_agent() -> Agent:
        agent = Agent(config, [], audit)
        agent.tools = build_tools(memory, audit, agent.now, agent.taint)
        if money is not None:
            agent.tools += build_money_tools(money, audit, agent.taint)
        agent.tools += payment_tools
        return agent

    if config.money_enabled:
        zone = ZoneInfo(config.owner_timezone)
        money = Money(memory, config.inbox_dir, audit, lambda: datetime.now(zone).date())
    chat_agent = make_agent()
    bot = Bot(config, chat_agent, approvals, nudger, audit)
    watchers = []
    if wise.mode == "draft":
        payments.notify = bot.send_owner
        watchers.append(payments_loop(payments, audit))
    webapp = WebApp(
        chat_agent, approvals, audit, money=money,
        settings={"model": config.model, "money": config.money_enabled, "wise_mode": wise.mode,
                  "wise_sandbox": wise.sandbox},
        memory_root=config.memory_dir,
    )
    await serve(webapp, config.api_socket)
    hour, minute = (int(part) for part in config.brief_time.split(":"))
    audit.write("luna.start", model=config.model)
    await asyncio.gather(
        bot.run(),
        brief_loop(make_agent, bot, audit, time(hour, minute), money),
        sync_loop(memory, audit),
        *watchers,
    )


def main() -> None:
    asyncio.run(run())
