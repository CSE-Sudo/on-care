"""건강 목표 어휘와 옛 질환 이름 정리. (#1814) DB 불필요."""
from __future__ import annotations

import pytest

from app.schemas.user import HealthGoalsUpdate, OnboardingRequest
from app.services import health_focus
from app.services.routine_suggestion_service import _BLOOD_PRESSURE_TERMS
from app.services.trainer_recommendation import _CONDITION_NEEDS, _EXERCISE_GOAL_NEEDS


def test_options_are_the_eight_member_goals_in_order():
    assert health_focus.FOCUS_OPTIONS == (
        "체중 감량",
        "근력 향상",
        "체력 강화",
        "자세 교정",
        "재활",
        "식습관 개선",
        "운동 습관",
        "혈압 관리",
    )


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        (None, None),
        ("", ""),
        ("혈압 관리, 체중 감량", "체중 감량, 혈압 관리"),
        ("고혈압, 당뇨 전단계", "혈압 관리"),
        ("비만, 고지혈증, 당뇨", "체중 감량"),
        ("고혈압, 혈압 관리", "혈압 관리"),
        ("무릎 통증으로 러닝 자제", "무릎 통증으로 러닝 자제"),
        ("당뇨, 무릎 통증, 근력 향상", "근력 향상, 무릎 통증"),
        # 건강 목표는 두 개까지 — 목록 순서로 앞의 둘만 남기고 다른 글은 지우지 않는다.
        ("재활, 체중 감량, 근력 향상, 무릎 통증", "체중 감량, 근력 향상, 무릎 통증"),
        ("고혈압, 비만, 체력 강화", "체중 감량, 체력 강화"),
    ],
)
def test_normalize_conditions(raw, expected):
    assert health_focus.normalize_conditions(raw) == expected


def test_focus_in_reads_legacy_names_as_new_goals():
    assert health_focus.focus_in("고혈압, 비만, 허리 통증") == ["체중 감량", "혈압 관리"]
    assert health_focus.focus_in(None) == []


def test_member_save_schemas_clean_legacy_names():
    assert OnboardingRequest(conditions="고혈압, 당뇨").conditions == "혈압 관리"
    assert HealthGoalsUpdate(conditions="비만").conditions == "체중 감량"
    # 보내지 않은 칸은 건드리지 않는다 — 수치만 고친 저장이 목표를 지우지 않는다.
    assert "conditions" not in HealthGoalsUpdate(daily_calories=2000).model_dump(
        exclude_unset=True
    )


def test_every_goal_feeds_trainer_recommendation():
    """고른 목표가 트레이너 추천 신호가 된다 — 빠진 목표는 추천에 아무 영향이 없다."""
    assert set(_CONDITION_NEEDS) == set(health_focus.FOCUS_OPTIONS)
    # 상담 신청의 운동 목표와 needs 가 **같은 객체**여야 두 신호가 하나로 합쳐진다.
    # 예전에는 표를 둘로 나눠 들다 한쪽만 고쳐졌다(#1992).
    for code, focus in health_focus.EXERCISE_GOAL_FOCUS.items():
        assert _EXERCISE_GOAL_NEEDS[code] is _CONDITION_NEEDS[focus]


def test_consultation_goals_are_the_eight_member_goals():
    """상담 운동 목표가 건강 목표 여덟 종과 1:1 이다. (#1992)

    예전에는 넷만 이어져, `건강 관리`·`기타` 를 고른 회원은 상담이 수락돼도
    건강 목표가 비어 있었다.
    """
    assert list(health_focus.EXERCISE_GOAL_FOCUS.values()) == list(
        health_focus.FOCUS_OPTIONS
    )
    assert list(health_focus.EXERCISE_GOAL_FOCUS) == [
        "weight_loss",
        "strength",
        "fitness",
        "posture",
        "rehab",
        "eating",
        "exercise_habit",
        "blood_pressure",
    ]


def test_create_accepts_exactly_those_goals_plus_other():
    """입력 Literal 과 매핑이 어긋나면 이을 곳 없는 값이 다시 생긴다. (#1992)"""
    from typing import get_args

    from app.schemas.consultation_api import ExerciseGoal

    accepted = set(get_args(ExerciseGoal))
    assert accepted == set(health_focus.EXERCISE_GOAL_FOCUS) | {"other"}
    # 없앤 `건강 관리` 는 새 신청으로 다시 들어오지 않는다.
    assert "health" not in accepted


def test_retired_goals_still_have_a_label_and_needs():
    """이미 저장된 요청은 백필하지 않는다 — 조회·복원만 깨지지 않으면 된다. (#1992)"""
    from app.services.consultation_service import _GOAL_LABELS

    # 여덟 목표는 건강 목표 문구를 그대로 쓴다 — 표를 따로 들다 `fitness` 하나가
    # `체력 증진` 으로 남았었다.
    for code, focus in health_focus.EXERCISE_GOAL_FOCUS.items():
        assert _GOAL_LABELS[code] == focus
    assert _GOAL_LABELS["health"] == "건강 관리"
    assert _GOAL_LABELS["other"] == "상담 후 설정"
    # 옛 값을 만나도 추천이 폴백으로 넘어간다.
    assert _EXERCISE_GOAL_NEEDS["health"].label == "건강 관리"
    assert "other" not in _EXERCISE_GOAL_NEEDS
    # 건강 목표로는 잇지 않는다 — 여덟 중 옮길 곳이 없다.
    assert health_focus.EXERCISE_GOAL_FOCUS.get("health") is None
    assert health_focus.EXERCISE_GOAL_FOCUS.get("other") is None


def test_blood_pressure_goal_still_softens_routine_suggestions():
    """'혈압 관리' 를 고른 회원도 운동 추천이 강도를 내리는 신호로 읽는다."""
    assert any(term in health_focus.FOCUS_BLOOD_PRESSURE for term in _BLOOD_PRESSURE_TERMS)


def test_member_can_keep_at_most_two_goals():
    assert health_focus.MAX_FOCUS == 2
    saved = HealthGoalsUpdate(conditions="혈압 관리, 재활, 운동 습관").conditions
    assert health_focus.focus_in(saved) == ["재활", "운동 습관"]


# --- 트레이너 화면 (#1818) -----------------------------------------------------


def test_focus_label_joins_goals_for_trainer_screens():
    assert health_focus.focus_label("혈압 관리, 체중 감량, 무릎 통증") == "체중 감량 · 혈압 관리"
    assert health_focus.focus_label("무릎 통증") == ""
    assert health_focus.focus_label(None) == ""


def test_with_focus_if_missing_never_overwrites_picked_goals():
    assert health_focus.with_focus_if_missing("", "체중 감량") == "체중 감량"
    assert health_focus.with_focus_if_missing("무릎 통증", "체중 감량") == "체중 감량, 무릎 통증"
    assert health_focus.with_focus_if_missing("근력 향상", "체중 감량") == "근력 향상"
    assert health_focus.with_focus_if_missing("고혈압", "체중 감량") == "혈압 관리"


def test_trainer_save_cleans_conditions_like_the_member_app():
    from app.schemas.trainer_api import MemberHealthProfileUpdate

    update = MemberHealthProfileUpdate(conditions="고혈압, 재활, 근력 향상, 무릎 통증")
    assert update.conditions == "근력 향상, 재활, 무릎 통증"


def test_demo_roster_goals_are_member_goals():
    from app.db.seed_trainer import _MEMBERS

    goals = [focus for _id, _e, _n, focus, _a, _d, _o in _MEMBERS]
    for focus in goals:
        assert health_focus.normalize_conditions(focus) == focus
        assert 1 <= len(health_focus.focus_in(focus)) <= health_focus.MAX_FOCUS
    # 여덟 목표가 데모 로스터 어딘가에 한 번은 나온다 — 트레이너 화면에서 모두 볼 수 있다.
    assert {f for g in goals for f in health_focus.focus_in(g)} == set(health_focus.FOCUS_OPTIONS)
