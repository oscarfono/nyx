from datetime import date

from luna_core.sysinfo import nixpkgs_date, update_notice

VERSION = "26.11.20261117.0490633"


def test_nixpkgs_date():
    assert nixpkgs_date(VERSION) == date(2026, 11, 17)


def test_no_notice_when_recent():
    assert update_notice(date(2026, 11, 30), VERSION) is None


def test_notice_when_old():
    notice = update_notice(date(2026, 12, 15), VERSION)
    assert notice is not None and "28 days" in notice


def test_notice_when_version_has_no_date():
    assert "cannot read a date" in update_notice(date(2026, 12, 15), "26.11")
