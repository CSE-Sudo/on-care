"""끌 수 없는 회원 알림 kind 와 수신 설정. (#2854)

회원 알림 설정 화면의 모든 스위치는 실제로 만들어지는 알림을 켜고 꺼야 한다.
쿠폰·챌린지 알림은 스위치가 없는 "끌 수 없는 알림" 이고, 그 사실이 `wants` 의
기본값이 아니라 [ALWAYS_DELIVERED] 상수에 드러나 있어야 한다.

DB 없이 돈다 — 설정 조회는 대역으로 바꾼다.
"""
from __future__ import annotations

import re
from contextlib import contextmanager
from pathlib import Path

import pytest

from app.services import notification_service

APP_DIR = Path(__file__).resolve().parents[1] / "app"


class _Session:
    """`wants` 가 쓰는 savepoint 만 흉내 낸다."""

    @contextmanager
    def begin_nested(self):
        yield


@pytest.fixture
def all_off(monkeypatch):
    """회원이 설정 스위치를 전부 끈 상태."""
    calls: list[str] = []

    def _settings(db, member_id):
        calls.append(member_id)
        return {key: False for key in notification_service.DEFAULTS}

    monkeypatch.setattr(notification_service, "get_settings", _settings)
    return calls


@pytest.mark.parametrize(
    "kind",
    [
        notification_service.POINTS_COUPON,
        notification_service.WEEKLY_CHALLENGE,
        notification_service.PT_LINK_NOTICE,
    ],
)
def test_always_delivered_kinds_ignore_the_settings(all_off, kind):
    assert notification_service.wants(_Session(), "member-1", kind) is True
    # 끌 수 없는 알림은 설정을 읽지도 않는다.
    assert all_off == []


@pytest.mark.parametrize(
    "kind",
    [
        notification_service.TRAINER_MESSAGE,
        notification_service.EXERCISE,
        notification_service.WEEKLY_REPORT,
    ],
)
def test_setting_keyed_kinds_follow_the_settings(all_off, kind):
    assert notification_service.wants(_Session(), "member-1", kind) is False


def test_always_delivered_kinds_are_not_settings():
    # 끌 수 없는 kind 가 설정 키와 겹치면 스위치가 있는데 꺼지지 않는다.
    assert notification_service.ALWAYS_DELIVERED.isdisjoint(
        notification_service.DEFAULTS
    )
    assert notification_service.ALWAYS_DELIVERED == {
        notification_service.POINTS_COUPON,
        notification_service.WEEKLY_CHALLENGE,
        notification_service.PT_LINK_NOTICE,
    }


def test_pt_link_notice_ignores_a_broken_settings_read(monkeypatch):
    """설정 조회가 터져도 일정·담당 알림은 설정을 읽지 않으므로 그대로 받는다."""

    def _boom(db, member_id):  # noqa: ANN001
        raise AssertionError("끌 수 없는 알림은 설정을 읽지 않는다")

    monkeypatch.setattr(notification_service, "get_settings", _boom)
    assert (
        notification_service.wants(
            _Session(), "member-1", notification_service.PT_LINK_NOTICE
        )
        is True
    )


def test_every_default_is_on():
    # 트레이너 주간 리포트도 기본 켜짐이다(#3025).
    assert all(notification_service.DEFAULTS.values())
    assert notification_service.DEFAULTS[notification_service.WEEKLY_REPORT] is True


def test_retired_keys_stay_in_the_settings_for_compatibility():
    # 앱은 식단 기록·AI 코칭 스위치를 더는 그리지 않지만, 이미 저장된 값과 예전
    # 앱 버전이 깨지지 않게 서버 설정 표에는 남는다.
    assert notification_service.DIET_LOG in notification_service.DEFAULTS
    assert notification_service.AI_COACHING in notification_service.DEFAULTS


def _queued_member_kinds() -> set[str]:
    """`notification_service.queue(...)` 호출부가 넘기는 kind 상수 이름들."""
    pattern = re.compile(
        r"notification_service\.queue\((?:(?!\n\s*\)\n).)*?kind=notification_service\.([A-Z_]+)",
        re.S,
    )
    found: set[str] = set()
    for path in APP_DIR.rglob("*.py"):
        found.update(pattern.findall(path.read_text(encoding="utf-8")))
    return found


def test_every_member_kind_is_a_setting_or_always_delivered():
    # 새 회원 알림 kind 를 만들면 스위치를 달거나 끌 수 없는 알림으로 밝혀야 한다.
    known = set(notification_service.DEFAULTS) | notification_service.ALWAYS_DELIVERED
    kinds = _queued_member_kinds()
    assert kinds, "queue 호출부를 찾지 못했다"
    for name in kinds:
        assert getattr(notification_service, name) in known, name


def test_no_member_notification_uses_the_retired_kinds():
    # 식단 기록·AI 코칭 알림을 만드는 곳이 없다 — 그래서 스위치를 뺐다.
    kinds = _queued_member_kinds()
    assert "DIET_LOG" not in kinds
    assert "AI_COACHING" not in kinds


def _queued_calls() -> list[str]:
    """`notification_service.queue(...)` 호출 하나하나의 인자 글."""
    pattern = re.compile(r"notification_service\.queue\((.*?)\n\s*\)", re.S)
    calls: list[str] = []
    for path in APP_DIR.rglob("*.py"):
        calls.extend(pattern.findall(path.read_text(encoding="utf-8")))
    return calls


@pytest.mark.parametrize(
    "category",
    ["MEMBER_SCHEDULE", "MEMBER_CONSULTATION", "MEMBER_COACH_INVITE"],
)
def test_schedule_and_link_notices_cannot_be_switched_off(category):
    """일정·담당 관계 알림은 끌 수 없는 kind 로만 나간다(#3024).

    예전에는 일정이 '운동 리마인더', 담당 해제·탈퇴가 '트레이너 메시지' 스위치에
    실려 있어, 그 스위치를 끈 회원이 PT 취소와 담당 해제를 듣지 못했다.
    """
    calls = [
        call
        for call in _queued_calls()
        if f"notification_service.{category}" in call
    ]
    assert calls, category
    for call in calls:
        assert "kind=notification_service.PT_LINK_NOTICE" in call, call


def test_routine_notices_still_follow_the_exercise_switch():
    """루틴·프로그램 배정은 '운동 루틴' 스위치로 끌 수 있다 — 기존 동작 그대로."""
    calls = [
        call
        for call in _queued_calls()
        if "notification_service.MEMBER_ROUTINE" in call
    ]
    assert calls
    for call in calls:
        assert "kind=notification_service.EXERCISE" in call, call
