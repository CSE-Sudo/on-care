"""테스트 세션 동안 '오늘'이 세션 시작일로 묶이는지 (#2940).

CI 실행이 KST 자정을 걸치면 시드(세션 시작 때 한 번)의 '오늘'과 요청 시점의
'오늘'이 하루 어긋나 무관한 테스트가 무더기로 깨졌다. 여기서는 실제 시계를
자정 직전·직후로 옮겨 가며 고정이 걸리는지 층별로 확인한다.

- 순수 단위: [SessionClockPin] 의 날짜·시각 계산
- 세션 픽스처: `clock.now/today/today_iso` 가 고정을 거치는지, 개별 테스트의
  monkeypatch 가 우선하는지
- DB: 자정을 넘긴 뒤에도 시드한 '오늘' 데이터가 요청의 '오늘'과 맞는지
"""
from __future__ import annotations

from datetime import date, datetime, timedelta

import pytest
from sqlalchemy import select

from app.core import clock
from tests.session_clock import SessionClockPin
from tests.test_trainer_schedule import _h, _tok

START = date(2026, 10, 1)
BEFORE_MIDNIGHT = datetime(2026, 10, 1, 23, 59, 30, tzinfo=clock.SEOUL)
AFTER_MIDNIGHT = datetime(2026, 10, 2, 0, 0, 30, tzinfo=clock.SEOUL)
NEXT_MORNING = datetime(2026, 10, 2, 9, 15, tzinfo=clock.SEOUL)


class _FakeSource:
    """옮겨 가며 읽히는 실제 시계 대역."""

    def __init__(self, moment: datetime) -> None:
        self.moment = moment

    def __call__(self) -> datetime:
        return self.moment


# ── 순수 단위 ──────────────────────────────────────────────────────────────


def test_pin_takes_the_start_date_from_the_source() -> None:
    pin = SessionClockPin(_FakeSource(BEFORE_MIDNIGHT))
    assert pin.start_date == START


def test_pin_passes_the_real_moment_through_on_the_start_day() -> None:
    source = _FakeSource(BEFORE_MIDNIGHT)
    pin = SessionClockPin(source)
    assert pin.now() == BEFORE_MIDNIGHT


def test_pin_keeps_the_start_date_after_midnight() -> None:
    source = _FakeSource(BEFORE_MIDNIGHT)
    pin = SessionClockPin(source)

    source.moment = AFTER_MIDNIGHT
    pinned = pin.now()

    assert pinned.date() == START
    assert (pinned.hour, pinned.minute, pinned.second) == (0, 0, 30)


def test_pin_lets_the_time_of_day_keep_moving() -> None:
    source = _FakeSource(BEFORE_MIDNIGHT)
    pin = SessionClockPin(source)

    source.moment = NEXT_MORNING
    pinned = pin.now()

    assert pinned.date() == START
    assert pinned.strftime("%H:%M") == "09:15"


def test_pin_keeps_the_kst_timezone() -> None:
    source = _FakeSource(BEFORE_MIDNIGHT)
    pin = SessionClockPin(source)

    source.moment = AFTER_MIDNIGHT
    pinned = pin.now()

    assert pinned.tzinfo is not None
    assert pinned.utcoffset() == timedelta(hours=9)


def test_pin_reads_the_same_day_before_and_after_midnight() -> None:
    source = _FakeSource(BEFORE_MIDNIGHT)
    pin = SessionClockPin(source)
    before = pin.now().date()

    source.moment = AFTER_MIDNIGHT
    after = pin.now().date()

    assert before == after == START


def test_pin_also_holds_when_the_session_starts_after_midnight() -> None:
    """00:00 직후에 시작한 세션은 그날을 계속 쓴다(시각이 다음 날로 가도)."""
    source = _FakeSource(AFTER_MIDNIGHT)
    pin = SessionClockPin(source)

    source.moment = datetime(2026, 10, 3, 0, 1, tzinfo=clock.SEOUL)
    assert pin.now().date() == date(2026, 10, 2)


# ── 세션 픽스처 ────────────────────────────────────────────────────────────


@pytest.fixture
def midnight_source(monkeypatch, session_clock_pin):
    """세션 고정의 실제 시계를 '시작일 23:59:30' 으로 옮긴다.

    반환한 대역의 `moment` 를 바꾸면 실제 시각이 자정을 넘은 상황이 된다.
    """
    assert session_clock_pin is not None
    start = session_clock_pin.start_date
    source = _FakeSource(datetime.combine(start, BEFORE_MIDNIGHT.timetz()))
    monkeypatch.setattr(session_clock_pin, "source", source)
    return source


def test_session_fixture_routes_clock_now_through_the_pin(session_clock_pin) -> None:
    assert session_clock_pin is not None
    assert clock.now().date() == session_clock_pin.start_date


def test_clock_today_holds_across_midnight(midnight_source, session_clock_pin) -> None:
    start = session_clock_pin.start_date
    assert clock.today() == start
    assert clock.today_iso() == start.isoformat()

    midnight_source.moment = midnight_source.moment + timedelta(minutes=1)
    assert midnight_source.moment.date() == start + timedelta(days=1)
    assert clock.today() == start
    assert clock.today_iso() == start.isoformat()
    assert clock.now().strftime("%H:%M") == "00:00"


def test_service_today_helpers_hold_across_midnight(
    midnight_source, session_clock_pin
) -> None:
    from app.services import diet_service, trainer_service

    start_iso = session_clock_pin.start_date.isoformat()
    midnight_source.moment = midnight_source.moment + timedelta(minutes=5)

    assert diet_service.today_str() == start_iso
    assert trainer_service.today_iso() == start_iso


def test_relative_time_label_reads_the_pinned_today(midnight_source) -> None:
    """채팅 시각 라벨도 같은 '오늘'을 본다 — 자정 뒤에 '어제'로 밀리지 않는다."""
    from app.services.trainer_service import relative_time_label

    seeded = clock.now().replace(hour=21, minute=10, second=0, microsecond=0)
    midnight_source.moment = midnight_source.moment + timedelta(minutes=5)

    assert relative_time_label(seeded) == "21:10"


def test_a_test_that_sets_its_own_clock_wins(monkeypatch, session_clock_pin) -> None:
    """개별 테스트의 monkeypatch 가 세션 고정보다 우선한다."""
    frozen = datetime(2001, 1, 2, 0, 30, tzinfo=clock.SEOUL)
    monkeypatch.setattr(clock, "now", lambda: frozen)

    assert clock.now() == frozen
    assert clock.today() == date(2001, 1, 2)
    assert session_clock_pin.start_date != date(2001, 1, 2)


def test_the_pin_comes_back_after_a_test_overrides_it(session_clock_pin) -> None:
    """바로 앞 테스트의 덮어쓰기가 끝나면 세션 고정으로 돌아온다."""
    assert clock.now == session_clock_pin.now
    assert clock.today() == session_clock_pin.start_date


# ── DB: 시드와 요청이 같은 '오늘' ──────────────────────────────────────────


def _trainer_headers(client) -> dict:
    return _h(_tok(client))


@pytest.mark.parametrize("minutes_after", [0, 1, 30])
def test_seeded_today_diet_matches_request_today_after_midnight(
    client, db_session, midnight_source, session_clock_pin, minutes_after
) -> None:
    """시드가 넣은 '오늘 3끼'의 날짜가 자정 직전·직후 모두 요청의 '오늘'과 같다."""
    from app.models.models import DietEntry

    midnight_source.moment = midnight_source.moment + timedelta(
        seconds=30, minutes=minutes_after
    )
    if minutes_after:
        assert midnight_source.moment.date() != session_clock_pin.start_date

    today_iso = clock.today_iso()
    assert today_iso == session_clock_pin.start_date.isoformat()
    seeded = db_session.scalars(
        select(DietEntry.id).where(
            DietEntry.engine == "seed", DietEntry.date == today_iso
        )
    ).all()
    assert seeded, "시드한 오늘 식단이 요청 기준 '오늘'에 보여야 한다"


@pytest.mark.parametrize("minutes_after", [0, 1])
def test_trainer_schedule_keeps_the_seeded_timeline_after_midnight(
    client, midnight_source, minutes_after
) -> None:
    """기본 날짜(오늘)로 묻는 스케줄이 자정 직후에도 시드 타임라인을 돌려준다."""
    midnight_source.moment = midnight_source.moment + timedelta(
        seconds=30, minutes=minutes_after
    )

    r = client.get("/v1/trainer/schedule", headers=_trainer_headers(client))
    assert r.status_code == 200, r.text
    slots = r.json()
    assert len(slots) >= 6
    assert any(len(s["program"]) > 0 for s in slots)
