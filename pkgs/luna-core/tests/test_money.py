import subprocess
from datetime import date
from decimal import Decimal

import pytest

from luna_core.audit import AuditLog
from luna_core.memory import Memory
from luna_core.money import Money
from luna_core.money_plan import load_plan
from luna_core.money_rules import RuleError, add_rule

RULES = "\n".join([
    "#+TITLE: Categories",
    "* Rules",
    "| Pattern | Account |",
    "|---------+---------|",
    "| woolworths | expenses:food:groceries |",
    "| transfer to | assets:transfers |",
    "| transfer from | assets:transfers |",
    "| afterpay | liabilities:afterpay |",
    "",
])

PLAN = "\n".join([
    "* Income",
    "| Source | Net per pay (AUD) | Pays per year | Net per year |",
    "| FIFO | 3,000.00 | 26 | |",
    "* Annual costs",
    "| Category | Item | Per year (AUD) | Due | Bucket |",
    "| Phone | Plan | 600 | Monthly | Bills |",
    "| Housing | Stays | 15,000 | Each swing | Bills |",
    "* Targets",
    "| Target | Per year (AUD) |",
    "| Buffer | 6,000 |",
    "| Invest | 10,000 |",
    "",
])

FILES = {
    "commbank--personal.csv": "\n".join([
        '20/11/2026,"-12.34","WOOLWORTHS 1234 PERTH Card xx4111 1111 1111 1111","+100.00"',
        '21/11/2026,"-500.00","Transfer to xx062000 12345678","-400.00"',
        '21/11/2026,"-9.99","NETFLIX","-409.99"',
    ]),
    "bendigo--savings.csv": '22/11/2026,"500.00","Transfer from CBA 12345678"\n',
    "up--spending.csv": "\n".join([
        "Time,Payee,Description,Total (AUD)",
        "2026-11-22T09:15:00+08:00,Afterpay,Repayment,-50.00",
    ]),
    "coopnz--everyday.csv": "Date,Details,Amount\n19/11/2026,Countdown,-20.50\n",
    "wise--main.csv": "\n".join([
        "TransferWise ID,Date,Amount,Currency,Description,Payee Name,Merchant",
        "TRANSFER-123456789,18-11-2026,-30.00,USD,Card transaction,,GitHub",
    ]),
}


@pytest.fixture
def money(tmp_path, monkeypatch):
    for name in ("GIT_AUTHOR_NAME", "GIT_COMMITTER_NAME"):
        monkeypatch.setenv(name, "test")
    for name in ("GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL"):
        monkeypatch.setenv(name, "test@example.com")
    root = tmp_path / "memory"
    (root / "money" / "tx").mkdir(parents=True)
    (root / "money" / "main.journal").write_text("include accounts.journal\ninclude tx/*.journal\n")
    (root / "money" / "accounts.journal").write_text("account assets  ; type: A\n")
    (root / "money" / "tx" / "opening.journal").write_text("; Opening balances.\n")
    (root / "money" / "categories.org").write_text(RULES)
    (root / "money.org").write_text(PLAN)
    subprocess.run(["git", "init", "--quiet", str(root)], check=True)
    subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(root), "commit", "--quiet", "-m", "seed"], check=True)
    inbox = tmp_path / "inbox"
    inbox.mkdir()
    memory = Memory(root, AuditLog(tmp_path / "audit.jsonl"), remote=False)
    return Money(memory, inbox, AuditLog(tmp_path / "audit.jsonl"), lambda: date(2026, 11, 23))


def upload(money, names):
    for name in names:
        (money.inbox / name).write_text(FILES[name])


def journal(money):
    return (money.root / "tx" / "2026.journal").read_text()


def test_import_all_profiles(money):
    upload(money, FILES)
    report = money.import_inbox()
    assert "Kept" not in report, report
    text = journal(money)
    assert "expenses:food:groceries  AUD 12.34" in text
    assert "assets:bank:commbank:personal  AUD -12.34" in text
    assert "liabilities:afterpay  AUD 50.00" in text
    assert "assets:bank:coopnz:everyday  NZD -20.50" in text
    assert "assets:bank:wise:main  USD -30.00" in text
    assert list(money.inbox.iterdir()) == []


def test_import_masks_numbers(money):
    upload(money, ["commbank--personal.csv"])
    money.import_inbox()
    text = journal(money)
    assert "4111 1111" not in text and "12345678" not in text
    assert "************1111" in text


def test_second_import_adds_nothing(money):
    upload(money, ["commbank--personal.csv"])
    money.import_inbox()
    first = journal(money)
    upload(money, ["commbank--personal.csv"])
    report = money.import_inbox()
    assert "0 new, 3 already imported" in report
    assert journal(money) == first


def test_import_commits_and_never_commits_csv(money):
    upload(money, ["up--spending.csv"])
    money.import_inbox()
    files = subprocess.run(["git", "-C", str(money.memory.root), "ls-files"],
                           capture_output=True, text=True).stdout
    assert "money/tx/2026.journal" in files
    assert ".csv" not in files


def test_wrong_header_keeps_the_file(money):
    (money.inbox / "up--spending.csv").write_text("Date,Thing,Value\n2026-11-22,x,1\n")
    report = money.import_inbox()
    assert "Kept up--spending.csv" in report and "Send LUNA the header row" in report
    assert (money.inbox / "up--spending.csv").exists()


def test_wrong_column_count_keeps_the_file(money):
    (money.inbox / "commbank--personal.csv").write_text("20/11/2026,-1.00,X\n")
    assert "expects 4" in money.import_inbox()


def test_bad_file_name_is_refused(money):
    (money.inbox / "statement.csv").write_text("x\n")
    assert "<profile>--<account>.csv" in money.import_inbox()


def test_transfers_cancel(money):
    upload(money, ["commbank--personal.csv", "bendigo--savings.csv"])
    money.import_inbox()
    assert "assets:transfers" not in money.summary()


def test_summary(money):
    upload(money, FILES)
    money.import_inbox()
    text = money.summary()
    assert "assets:bank:commbank:personal | AUD -522.33" in text
    # 3000 * 26 = 78000; minus 15600 costs, 6000 buffer, 10000 invest; / 52
    assert "Safe to spend per week: AUD 892.31" in text
    assert "no category" in text


def test_unknown_lists_masked_transactions(money):
    upload(money, ["commbank--personal.csv"])
    money.import_inbox()
    text = money.unknown()
    assert "NETFLIX" in text and "WOOLWORTHS" not in text


def test_plan_reports_missing_income(tmp_path):
    path = tmp_path / "money.org"
    path.write_text("* Income\n| Source | Net per pay (AUD) | Pays per year | Net per year |\n| FIFO | | | |\n")
    plan = load_plan(path)
    assert plan.spend_per_week is None and plan.missing



@pytest.mark.parametrize("pattern, account", [("a|b", "expenses:x"), ("(", "expenses:x"), ("ok", "Expenses")])
def test_bad_rules_are_refused(tmp_path, pattern, account):
    path = tmp_path / "categories.org"
    path.write_text(RULES)
    with pytest.raises(RuleError):
        add_rule(path, pattern, account)


def test_old_main_journal_is_refused(money):
    money.main.write_text("~ every 4 weeks  pay\n    assets:income  AUD 0\n    income:fifo\n")
    upload(money, ["commbank--personal.csv"])
    assert "include tx/*.journal" in money.import_inbox()
    assert (money.inbox / "commbank--personal.csv").exists()


def test_add_rule_applies_to_next_import(money):
    assert "Added" in money.add_rule("netflix", "expenses:subscriptions")
    upload(money, ["commbank--personal.csv"])
    money.import_inbox()
    assert "expenses:subscriptions  AUD 9.99" in journal(money)
