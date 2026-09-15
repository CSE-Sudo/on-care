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
    # 상담 신청의 운동 목표와 라벨이 같아야 두 신호가 하나로 합쳐진다.
    consult_labels = {need.label for need in _EXERCISE_GOAL_NEEDS.values()}
    for focus in ("체중 감량", "근력 향상", "체력 강화", "자세 교정"):
        assert _CONDITION_NEEDS[focus].label in consult_labels


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


def test_consultation_goals_map_onto_member_goals():
    assert set(health_focus.EXERCISE_GOAL_FOCUS.values()) <= set(health_focus.FOCUS_OPTIONS)


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
