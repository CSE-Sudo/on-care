"""주 시작 계산 단일 헬퍼 `app.core.week.monday_of` (#2908).

서비스·시드가 저마다 적던 `day - timedelta(days=day.weekday())` 를 이 헬퍼로
모았다. 기존 래퍼(`monday_of_str`·`week_monday`·`week_start_of`)도 같은 값을
내는지, 앱 공용 규칙과 이메일 길이 상한이 어긋나지 않는지 함께 고정한다.
"""
from __future__ import annotations

import re
from datetime import date, timedelta
from pathlib import Path

import pytest

from app.core.week import monday_of
from app.services import contact_format, period_window
from app.services.exercise_service import monday_of_str, weekday_label_of
from app.services.weekly_challenge_service import week_monday

_ROOT = Path(__file__).resolve().parents[2]


@pytest.mark.parametrize(
    ("day", "expected"),
    [
        (date(2026, 9, 28), date(2026, 9, 28)),  # 월요일은 그대로
        (date(2026, 10, 4), date(2026, 9, 28)),  # 일요일은 그 주 월요일
        (date(2026, 10, 1), date(2026, 9, 28)),
        (date(2027, 1, 1), date(2026, 12, 28)),  # 해를 넘는 주
        (date(2028, 3, 1), date(2028, 2, 28)),  # 윤년 2월 29일을 지난다
    ],
)
def test_monday_of_returns_week_monday(day: date, expected: date) -> None:
    assert monday_of(day) == expected


def test_monday_of_covers_every_day_of_a_week() -> None:
    monday = date(2026, 9, 28)
    for offset in range(7):
        day = monday + timedelta(days=offset)
        assert monday_of(day) == monday
        assert monday_of(day).weekday() == 0


def test_wrappers_agree_with_monday_of() -> None:
    for offset in range(14):
        day = date(2026, 12, 21) + timedelta(days=offset)
        assert monday_of_str(day.isoformat()) == monday_of(day).isoformat()
        assert week_monday(day) == monday_of(day)


def test_period_window_week_starts_on_monday() -> None:
    start, end = period_window.period_bounds(
        period_window.PERIOD_WEEK, date(2026, 10, 3)
    )
    assert (start, end) == ("2026-09-28", "2026-10-03")


def test_no_direct_weekday_subtraction_left_in_services_and_seeds() -> None:
    """월요일 계산을 다시 직접 적지 않도록 서비스·시드를 훑는다."""
    pattern = re.compile(r"timedelta\(days=[\w.]+\.weekday\(\)")
    offenders = [
        str(path.relative_to(_ROOT))
        for folder in ("backend/app/services", "backend/app/db")
        for path in sorted((_ROOT / folder).rglob("*.py"))
        if pattern.search(path.read_text(encoding="utf-8"))
    ]
    assert offenders == []


def test_app_email_limit_matches_server() -> None:
    """앱 공용 입력 규칙의 이메일 상한이 서버 `EMAIL_MAX_LENGTH` 와 같다."""
    rules = (
        _ROOT / "shared/oncare_ui/lib/src/forms/app_input_rules.dart"
    ).read_text(encoding="utf-8")
    found = re.search(r"static const int emailMaxLength = (\d+);", rules)
    assert found is not None
    assert int(found.group(1)) == contact_format.EMAIL_MAX_LENGTH


# ---------- 깨진 날짜는 조용히 대체하지 않는다(#3256) ----------


def test_weekday_label_of_returns_the_day_label() -> None:
    assert weekday_label_of("2026-09-28") == "월"
    assert weekday_label_of("2026-10-04") == "일"


@pytest.mark.parametrize("bad", ["", "2026-13-01", "2026-02-30", "not-a-date", None])
def test_monday_of_str_rejects_a_broken_day(bad) -> None:
    """예전에는 이번 주 월요일로 떨어져 엉뚱한 주를 읽었다."""
    with pytest.raises(ValueError):
        monday_of_str(bad)


@pytest.mark.parametrize("bad", ["", "2026-13-01", "2026-02-30", "not-a-date", None])
def test_weekday_label_of_rejects_a_broken_day(bad) -> None:
    """예전에는 오늘 요일로 떨어져 엉뚱한 날의 기록을 골랐다."""
    with pytest.raises(ValueError):
        weekday_label_of(bad)
