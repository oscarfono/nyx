from datetime import datetime, time

from luna_core.scheduler import next_run


def test_next_run_is_today_before_the_time():
    assert next_run(datetime(2026, 11, 20, 6, 0), time(7, 0)) == datetime(2026, 11, 20, 7, 0)


def test_next_run_is_tomorrow_after_the_time():
    assert next_run(datetime(2026, 11, 20, 8, 0), time(7, 0)) == datetime(2026, 11, 21, 7, 0)
