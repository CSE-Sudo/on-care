"""목록 오른쪽 위 시각 문구 — 오늘이면 HH:MM, 어제면 '어제', 그 전이면 날짜.

카카오톡과 같은 규칙이다. 예전에는 "방금/N분 전/N시간 전/N일 전" 으로 흘러간
시간을 셌는데, 며칠씩 지난 대화에서 트레이너가 알고 싶은 것은 "얼마나 됐나" 가
아니라 **언제였나** 다 — 그건 운동·식단 기록과 맞춰 보려면 날짜여야 한다.
"""
from __future__ import annotations

from datetime import timedelta, timezone

from app.core import clock
from app.services.trainer._common import relative_time_label


def test_today_shows_the_clock() -> None:
    ts = clock.now().replace(hour=18, minute=18, second=0, microsecond=0)
    assert relative_time_label(ts) == "18:18"


def test_yesterday_says_yesterday() -> None:
    assert relative_time_label(clock.now() - timedelta(days=1)) == "어제"


def test_older_shows_the_date() -> None:
    ts = clock.now() - timedelta(days=3)
    assert relative_time_label(ts) == ts.date().isoformat()


def test_boundary_is_the_kst_calendar_day_not_elapsed_hours() -> None:
    """KST 새벽에 받은 메시지는 23시간 가까이 지나도 '오늘' 이다.

    흘러간 초로 나누면 그 메시지가 '어제' 로 밀린다.
    """
    now = clock.now()
    early = now.replace(hour=1, minute=5, second=0, microsecond=0)
    if early > now:
        return  # 아직 01:05 전이라면 그 시각은 오늘 오지 않았다.
    assert relative_time_label(early) == "01:05"


def test_naive_timestamps_are_read_as_utc() -> None:
    """DB 의 `created_at` 은 tz 없는 UTC 로 온다 — KST 로 옮겨 판정한다."""
    aware = clock.now() - timedelta(days=2)
    naive_utc = aware.astimezone(timezone.utc).replace(tzinfo=None)
    assert relative_time_label(naive_utc) == aware.date().isoformat()
