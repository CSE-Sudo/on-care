"""서비스 기준 시각이 서버 타임존과 무관하게 KST 인지 — DB 불필요 (#557).

배포 이미지(`python:3.12-slim`)의 기본 타임존은 UTC 다. 서버 로컬 시간을 쓰면
KST 00:00~09:00 사이에 서비스가 판단하는 '오늘'이 하루 전이 되어, 아침에 기록한
식사가 전날 식단으로 들어가고 '오늘/어제' 라벨이 밀린다. 이 테스트는 프로세스
타임존을 UTC 로 바꿔 놓고도 도메인 날짜가 KST 를 따르는지 고정한다.
"""
from __future__ import annotations

import os
import time
from datetime import datetime, timedelta, timezone

import pytest

from app.core import clock

KST_OFFSET_SECONDS = 9 * 3600


@pytest.fixture
def utc_process_tz():
    """프로세스 로컬 타임존을 UTC 로 바꾼다 — 배포 컨테이너와 같은 상태."""
    if not hasattr(time, "tzset"):
        pytest.skip("tzset 을 지원하지 않는 플랫폼")
    original = os.environ.get("TZ")
    os.environ["TZ"] = "UTC"
    time.tzset()
    try:
        yield
    finally:
        if original is None:
            os.environ.pop("TZ", None)
        else:
            os.environ["TZ"] = original
        time.tzset()


@pytest.fixture
def real_clock(monkeypatch, session_clock_pin):
    """세션 날짜 고정(#2940)을 걷어 내고 실제 `clock.now` 로 검증한다.

    이 파일은 clock 구현 자체가 KST 를 따르는지 보는 곳이라, 세션 고정이 아니라
    원본 시계를 실제 현재 시각과 비교해야 한다.
    """
    if session_clock_pin is not None:
        monkeypatch.setattr(clock, "now", session_clock_pin.source)


def _kst_today():
    """테스트가 기대하는 KST 오늘 — clock 구현과 독립적으로 계산한다."""
    return datetime.now(timezone.utc).astimezone(clock.SEOUL).date()


def test_now_is_tz_aware_kst(utc_process_tz, real_clock):
    now = clock.now()
    assert now.tzinfo is not None, "naive 시각은 서버 TZ 에 휘둘린다"
    assert now.utcoffset().total_seconds() == KST_OFFSET_SECONDS


def test_today_follows_kst_not_server_tz(utc_process_tz, real_clock):
    expected = _kst_today()
    assert clock.today() == expected
    assert clock.today_iso() == expected.isoformat()


def test_kst_early_morning_is_not_previous_day():
    """KST 새벽은 UTC 로는 전날 — 하루 밀리던 구간을 고정한다."""
    # 2026-08-10 00:30 KST == 2026-08-09 15:30 UTC
    instant = datetime(2026, 8, 9, 15, 30, tzinfo=timezone.utc)
    assert instant.date().isoformat() == "2026-08-09"  # UTC 기준으로는 전날
    assert clock.to_seoul(instant).date().isoformat() == "2026-08-10"


def test_to_seoul_treats_naive_as_utc():
    """created_at 은 UTC naive 로 저장되므로 UTC 로 간주해야 한다."""
    naive = datetime(2026, 8, 9, 15, 30)
    converted = clock.to_seoul(naive)
    assert converted.date().isoformat() == "2026-08-10"
    assert converted.strftime("%H:%M") == "00:30"


def test_domain_today_helpers_use_kst(utc_process_tz, real_clock):
    """서비스 계층의 '오늘'이 전부 KST 를 따르는지 — 회귀 방지."""
    from app.services import diet_service, exercise_service, trainer_service

    expected = _kst_today()
    assert diet_service.today_str() == expected.isoformat()
    assert trainer_service.today_iso() == expected.isoformat()

    monday = expected - timedelta(days=expected.weekday())
    assert exercise_service.monday_of_this_week_str() == monday.isoformat()


def test_domain_today_helpers_at_kst_early_morning(monkeypatch, utc_process_tz):
    """KST 새벽 시각을 고정해 도메인 '오늘'을 검증한다.

    실제 현재 시각에 기대면 KST 00:00~08:59 가 아닌 시간대에는 `date.today()`
    같은 서버 로컬 날짜 회귀가 있어도 통과한다(UTC 와 KST 날짜가 같으므로).
    문제 구간을 고정해야 회귀가 항상 잡힌다.
    """
    from app.services import diet_service, exercise_service, trainer_service

    # 2026-03-02(월) 00:30 KST == 2026-03-01(일) 15:30 UTC.
    # 일부러 **주가 갈리는** 시각을 골랐다 — UTC 로 밀리면 날짜뿐 아니라 주차까지
    # 어긋나서, 어느 한쪽만 회귀해도 아래 단언이 잡는다.
    frozen = datetime(2026, 3, 1, 15, 30, tzinfo=timezone.utc).astimezone(clock.SEOUL)
    monkeypatch.setattr(clock, "now", lambda: frozen)

    # 서버 로컬(UTC)로는 2026-03-01 이지만 서비스는 KST 날짜를 써야 한다.
    assert clock.today().isoformat() == "2026-03-02"
    assert clock.today_iso() == "2026-03-02"
    assert diet_service.today_str() == "2026-03-02"
    assert trainer_service.today_iso() == "2026-03-02"
    # KST 로는 월요일 당일이 주 시작. UTC(일요일)로 읽으면 2026-02-23 이 된다.
    assert exercise_service.monday_of_this_week_str() == "2026-03-02"


def test_trainer_labels_use_kst_dates():
    """채팅 시각·이력 날짜 라벨이 UTC 가 아니라 KST 로 찍힌다."""
    from app.services import trainer_service

    # 2026-08-10 00:30 KST 에 저장된 메시지(UTC naive 로 보관된 형태)
    created_at = datetime(2026, 8, 9, 15, 30)
    assert trainer_service._hhmm(created_at) == "00:30"
    assert trainer_service._local_date_iso(created_at) == "2026-08-10"
