import asyncio
import base64
import stat

import aiohttp
from aiohttp.test_utils import TestClient, TestServer

from luna_core.approvals import Approvals
from luna_core.audit import AuditLog
from luna_core.web import WebApp, serve


class FakeAgent:
    def __init__(self):
        self.asked = []

    async def ask(self, text, images=()):
        self.asked.append((text, list(images)))
        return "reply: " + text

    def transcript(self):
        return [{"role": "user", "text": "hello"}, {"role": "assistant", "text": "hi"}]


def make(tmp_path):
    (tmp_path / "approvals").mkdir()
    audit = AuditLog(tmp_path / "audit.jsonl")
    (tmp_path / "audit.jsonl").write_text("")
    approvals = Approvals(tmp_path / "approvals", audit)
    calls = []

    async def executor(params):
        calls.append(params)
        return "done"

    approvals.register("test", executor)
    agent = FakeAgent()
    return WebApp(agent, approvals, audit), agent, approvals, calls


def run(webapp, scenario):
    async def go():
        async with TestClient(TestServer(webapp.app())) as client:
            return await scenario(client)
    return asyncio.run(go())


def test_history(tmp_path):
    webapp, *_ = make(tmp_path)
    async def scenario(client):
        return await (await client.get("/api/history")).json()
    assert run(webapp, scenario)["messages"][1] == {"role": "assistant", "text": "hi"}


def test_chat_with_an_image(tmp_path):
    webapp, agent, *_ = make(tmp_path)
    data = base64.b64encode(b"\xff\xd8fake-jpeg").decode()
    async def scenario(client):
        response = await client.post("/api/chat",
                                     json={"text": "what is this?", "image": {"media_type": "image/jpeg", "data": data}})
        return response.status, await response.json()
    status, body = run(webapp, scenario)
    assert status == 200 and body["reply"] == "reply: what is this?"
    assert agent.asked == [("what is this?", [("image/jpeg", data)])]


def test_bad_image_is_refused(tmp_path):
    webapp, agent, *_ = make(tmp_path)
    async def scenario(client):
        a = await client.post("/api/chat", json={"text": "x", "image": {"media_type": "image/gif", "data": "AA=="}})
        b = await client.post("/api/chat", json={"text": "x", "image": {"media_type": "image/png", "data": "not base64!"}})
        return a.status, b.status
    assert run(webapp, scenario) == (400, 400)
    assert agent.asked == []


def test_approve(tmp_path):
    webapp, _, approvals, calls = make(tmp_path)
    item = asyncio.run(approvals.request("test", {"x": 1}, "Test payment"))
    async def scenario(client):
        listed = await (await client.get("/api/approvals")).json()
        result = await (await client.post(f"/api/approvals/{item.id}/approve", json={})).json()
        return listed, result
    listed, result = run(webapp, scenario)
    assert listed["approvals"][0]["summary"] == "Test payment"
    assert result["result"] == "done" and calls == [{"x": 1}]


def test_money_is_off_by_default(tmp_path):
    webapp, *_ = make(tmp_path)
    async def scenario(client):
        return await (await client.get("/api/money")).json()
    assert "Money is off" in run(webapp, scenario)["text"]


def test_system(tmp_path):
    webapp, *_ = make(tmp_path)
    async def scenario(client):
        return await (await client.get("/api/system")).json()
    data = run(webapp, scenario)
    assert data["pending_approvals"] == 0 and "update" in data


def test_serve_on_a_unix_socket(tmp_path):
    webapp, *_ = make(tmp_path)
    path = tmp_path / "api.sock"
    path.write_text("an old socket")
    async def go():
        await serve(webapp, path)
        connector = aiohttp.UnixConnector(path=str(path))
        async with aiohttp.ClientSession(connector=connector) as session:
            async with session.get("http://core/api/money") as response:
                return await response.json()
    assert "Money is off" in asyncio.run(go())["text"]
    assert stat.S_ISSOCK(path.stat().st_mode)
