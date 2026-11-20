import asyncio
import base64

from aiohttp.test_utils import TestClient, TestServer

from luna_core.approvals import Approvals
from luna_core.audit import AuditLog
from luna_core.web import WebApp

OWNER = "cooper@oscarfono.com"
ORIGIN = "https://luna.example.ts.net:8443"
GOOD = {"Tailscale-User-Login": OWNER, "Origin": ORIGIN, "X-Luna": "1"}


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
    return WebApp(agent, approvals, audit, OWNER, ORIGIN), agent, approvals, calls


def run(webapp, scenario):
    async def go():
        async with TestClient(TestServer(webapp.app())) as client:
            return await scenario(client)
    return asyncio.run(go())


def test_no_login_is_refused(tmp_path):
    webapp, *_ = make(tmp_path)
    async def scenario(client):
        return (await client.get("/")).status, (await client.get("/", headers={"Tailscale-User-Login": "x@y"})).status
    assert run(webapp, scenario) == (403, 403)


def test_owner_gets_the_page_with_a_strict_policy(tmp_path):
    webapp, *_ = make(tmp_path)
    async def scenario(client):
        response = await client.get("/", headers={"Tailscale-User-Login": OWNER})
        return response.status, response.headers["Content-Security-Policy"], await response.text()
    status, csp, text = run(webapp, scenario)
    assert status == 200 and "script-src 'self'" in csp and "<title>LUNA</title>" in text


def test_post_needs_origin_and_header(tmp_path):
    webapp, agent, *_ = make(tmp_path)
    async def scenario(client):
        bad = await client.post("/api/chat", json={"text": "x"}, headers={"Tailscale-User-Login": OWNER})
        other = await client.post("/api/chat", json={"text": "x"},
                                  headers={**GOOD, "Origin": "https://evil.example"})
        return bad.status, other.status
    assert run(webapp, scenario) == (403, 403)
    assert agent.asked == []


def test_chat_with_an_image(tmp_path):
    webapp, agent, *_ = make(tmp_path)
    data = base64.b64encode(b"\xff\xd8fake-jpeg").decode()
    async def scenario(client):
        response = await client.post("/api/chat", headers=GOOD,
                                     json={"text": "what is this?", "image": {"media_type": "image/jpeg", "data": data}})
        return response.status, await response.json()
    status, body = run(webapp, scenario)
    assert status == 200 and body["reply"] == "reply: what is this?"
    assert agent.asked == [("what is this?", [("image/jpeg", data)])]


def test_bad_image_is_refused(tmp_path):
    webapp, agent, *_ = make(tmp_path)
    async def scenario(client):
        a = await client.post("/api/chat", headers=GOOD, json={"text": "x", "image": {"media_type": "image/gif", "data": "AA=="}})
        b = await client.post("/api/chat", headers=GOOD, json={"text": "x", "image": {"media_type": "image/png", "data": "not base64!"}})
        return a.status, b.status
    assert run(webapp, scenario) == (400, 400)
    assert agent.asked == []


def test_approve_from_the_page(tmp_path):
    webapp, _, approvals, calls = make(tmp_path)
    item = asyncio.run(approvals.request("test", {"x": 1}, "Test payment"))
    async def scenario(client):
        listed = await (await client.get("/api/approvals", headers=GOOD)).json()
        result = await (await client.post(f"/api/approvals/{item.id}/approve", headers=GOOD, json={})).json()
        return listed, result
    listed, result = run(webapp, scenario)
    assert listed["approvals"][0]["summary"] == "Test payment"
    assert result["result"] == "done" and calls == [{"x": 1}]


def test_money_is_off_by_default(tmp_path):
    webapp, *_ = make(tmp_path)
    async def scenario(client):
        return await (await client.get("/api/money", headers=GOOD)).json()
    assert "Money is off" in run(webapp, scenario)["text"]


def test_system_panel(tmp_path):
    webapp, *_ = make(tmp_path)
    async def scenario(client):
        return await (await client.get("/api/system", headers=GOOD)).json()
    data = run(webapp, scenario)
    assert data["pending_approvals"] == 0 and "update" in data
