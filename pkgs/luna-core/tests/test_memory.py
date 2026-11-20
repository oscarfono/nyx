import subprocess
from datetime import datetime

import pytest

from luna_core.audit import AuditLog
from luna_core.memory import Memory, MemoryAccessError


@pytest.fixture
def memory(tmp_path, monkeypatch):
    for name in ("GIT_AUTHOR_NAME", "GIT_COMMITTER_NAME"):
        monkeypatch.setenv(name, "test")
    for name in ("GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL"):
        monkeypatch.setenv(name, "test@example.com")
    root = tmp_path / "memory"
    root.mkdir()
    subprocess.run(["git", "init", "--quiet", str(root)], check=True)
    (root / "notes.org").write_text("* Notes\nThe base costs AUD 900 per month.\n")
    subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(root), "commit", "--quiet", "-m", "seed"], check=True)
    return Memory(root, AuditLog(tmp_path / "audit.jsonl"), remote=False)


@pytest.mark.parametrize("path", ["/etc/passwd", "../outside.org", ".git/config", "notes.txt", "a/../../x.org"])
def test_paths_outside_the_rules_are_refused(memory, path):
    with pytest.raises(MemoryAccessError):
        memory.resolve(path)


def test_search_ignores_case(memory):
    assert memory.search("BASE COSTS") == ["notes.org:2: The base costs AUD 900 per month."]


def test_append_makes_a_commit(memory):
    memory.append("travel.org", "Bali in March", "- Budget: AUD 60 per night", datetime(2026, 11, 20, 7, 0))
    assert "* Bali in March" in memory.read("travel.org")
    log = subprocess.run(["git", "-C", str(memory.root), "log", "--oneline"], capture_output=True, text=True).stdout
    assert "Bali in March" in log
