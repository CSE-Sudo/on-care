"""주간 운동 응답의 `date_label` 은 요일이 아니라 실제 날짜로 정한다. (#3251)

요일만 보면 지난주 수요일 기록도 오늘이 수요일이면 `오늘` 이 됐다. 두 앱은 이 값을
그리지 않지만 계약 값이 틀리면 그 값을 쓰기 시작하는 화면이 틀린다. DB 없이 돈다.
"""
from __future__ import annotations

from datetime import datetime
from types import SimpleNamespace

import pytest

from app.core import clock
from app.services.exercise_service import build_current_week

#: 2026-10-07(수) 12:00 KST.
_NOW = datetime(2026, 10, 7, 12, 0, tzinfo=clock.SEOUL)


@pytest.fixture(autouse=True)
def _wednesday(monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: _NOW)


def _row(week_start: str, day_label: str) -> SimpleNamespace:
    return SimpleNamespace(
        id=f"ex-{week_start}-{day_label}", week_start=week_start, day_label=day_label,
        type="cardio", name="걷기", minutes=30, calories=100, completed_at=None,
    )


def _label(week_start: str, day_label: str) -> str:
    [session] = build_current_week([_row(week_start, day_label)])["sessions"]
    return session["date_label"]


def test_this_week_labels_are_unchanged():
    assert _label("2026-10-05", "수") == "오늘"
    assert _label("2026-10-05", "화") == "어제"
    assert _label("2026-10-05", "월") == "10월 5일"
    assert _label("2026-10-05", "금") == "금요일"  # 아직 오지 않은 날


def test_last_week_same_weekday_is_not_today():
    assert _label("2026-09-28", "수") == "9월 30일"
    assert _label("2026-09-28", "화") == "9월 29일"
    assert _label("2026-09-28", "일") == "10월 4일"
