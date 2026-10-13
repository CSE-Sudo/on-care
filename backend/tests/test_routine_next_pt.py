"""AI 루틴 C안 — 지난 PT 흐름상 다음 차례(#3282).

차례는 규칙이 정한다: 두 번 이상 반복된 프로그램이 둘 이상이면(순환) 그중
가장 오래 안 한 것, 순환이 보이지 않으면 가장 최근 PT, 기록이 없으면 전신
기본 프로그램. C안은 늘 있다.
"""
from __future__ import annotations

from datetime import date, timedelta

from app.schemas.trainer_api import RoutineOptionAnalysisOut, RoutineOptionsRequest
from app.services import routine_next_pt
from app.services.routine_next_pt import PtItem, PtSession, choose_next, rule_plan_c
from app.services.trainer_routine_options_service import (
    _pt_items,
    build_rule_options,
)

TODAY = date(2026, 10, 6)

CHEST = (
    PtItem("벤치프레스", "근력", sets=4, reps=10, weight=40),
    PtItem("랫풀다운", "근력", sets=3, reps=12, weight=30),
    PtItem("마무리 러닝머신", "유산소", minutes=15),
)
LEGS = (
    PtItem("레그프레스", "근력", sets=4, reps=12, weight=80),
    PtItem("런지", "근력", sets=3, reps=10),
    PtItem("마무리 러닝머신", "유산소", minutes=15),
)
SHOULDER = (
    PtItem("숄더프레스", "근력", sets=4, reps=10, weight=20),
    PtItem("인클라인 푸시업", "근력", sets=3, reps=12),
    PtItem("마무리 러닝머신", "유산소", minutes=10),
)


def _sessions(*programs) -> list[PtSession]:
    """최신 먼저, 한 주 간격."""
    return [
        PtSession(day=TODAY - timedelta(days=7 * (i + 1)), items=items)
        for i, items in enumerate(programs)
    ]


def test_no_records_starts_full_body():
    nxt = choose_next([], today=TODAY)
    assert nxt.kind == "start"
    assert nxt.items
    assert "전신" in nxt.basis


def test_picks_the_rotated_program_done_longest_ago():
    # 최신부터: 가슴 · 하체 · 어깨 · 가슴 · 하체 · 어깨 — 어깨가 가장 오래전(3주 전).
    nxt = choose_next(
        _sessions(CHEST, LEGS, SHOULDER, CHEST, LEGS, SHOULDER), today=TODAY
    )
    assert nxt.kind == "rotation"
    assert nxt.items == SHOULDER
    assert nxt.days_ago == 21
    assert "숄더프레스" in nxt.label


def test_programs_that_never_repeat_continue_the_latest():
    # 전신·서킷처럼 매번 구성이 다르면 순환이 아니다 — 가장 오래된 회차를
    # "차례" 로 고르지 않고 가장 최근 PT 를 이어 간다.
    nxt = choose_next(_sessions(CHEST, LEGS, SHOULDER), today=TODAY)
    assert nxt.kind == "continue"
    assert nxt.items == CHEST


def test_one_repeated_program_is_not_a_rotation():
    nxt = choose_next(_sessions(LEGS, CHEST, SHOULDER, CHEST), today=TODAY)
    assert nxt.kind == "continue"
    assert nxt.items == LEGS


def test_finishing_stretch_and_cardio_do_not_split_programs():
    # 마무리 유산소 시간만 다른 같은 가슴 날은 한 프로그램이다.
    chest_short = (*CHEST[:2], PtItem("마무리 러닝머신", "유산소", minutes=10))
    nxt = choose_next(_sessions(CHEST, chest_short), today=TODAY)
    assert nxt.kind == "continue"


def test_single_program_continues_the_same_flow():
    nxt = choose_next(_sessions(LEGS), today=TODAY)
    assert nxt.kind == "continue"
    assert nxt.items == LEGS


def test_rule_plan_c_swaps_risky_moves_and_fits_minutes():
    nxt = choose_next(_sessions(LEGS), today=TODAY)
    plan = rule_plan_c(
        nxt,
        available_minutes=20,
        intensity_preference="moderate",
        avg_completion_rate=70,
        cautions=["무릎"],
        escalate=False,
    )
    names = [e["name"] for e in plan["exercises"]]
    assert "런지" not in names
    assert any("런지 →" in c and "무릎" in c for c in plan["changes"])
    assert plan["total_minutes"] == sum(e["minutes"] for e in plan["exercises"])
    assert plan["total_minutes"] <= 20
    assert plan["basis"] == nxt.basis


def test_rule_plan_c_steps_sets_by_completion():
    nxt = choose_next(_sessions(CHEST), today=TODAY)
    up = rule_plan_c(
        nxt, available_minutes=180, intensity_preference="moderate",
        avg_completion_rate=90, cautions=[], escalate=False,
    )
    assert up["exercises"][0]["sets"] == 5
    held = rule_plan_c(
        nxt, available_minutes=180, intensity_preference="moderate",
        avg_completion_rate=90, cautions=[], escalate=True,
    )
    # 판단이 어려운 상태에서는 올리지 않는다.
    assert held["exercises"][0]["sets"] == 4
    down = rule_plan_c(
        nxt, available_minutes=180, intensity_preference="moderate",
        avg_completion_rate=30, cautions=[], escalate=False,
    )
    assert down["exercises"][0]["sets"] == 3


def test_pt_items_reads_loose_legacy_values():
    items = _pt_items(
        '[{"name": "스쿼트", "sets": "3세트", "reps": "10회", "weight": "20kg"},'
        ' {"name": "걷기", "type": "유산소", "duration_seconds": 600}]'
    )
    assert items[0].sets == 3 and items[0].reps == 10 and items[0].weight == 20
    assert items[1].minutes == 10


def test_rule_options_always_carry_plan_c_and_rotation_finding():
    analysis = RoutineOptionAnalysisOut(
        goal="체중 감량",
        sodium_today_mg=1500,
        sodium_over_target=False,
        avg_completion_rate=70,
        latest_routine="",
        note="",
    )
    request = RoutineOptionsRequest(available_minutes=30, intensity_preference="moderate")
    options = build_rule_options(
        analysis, request, next_pt=choose_next([], today=TODAY)
    )
    assert options.plan_c is not None
    assert options.plan_c.key == "C"
    assert options.plan_c.total_minutes <= 30
    assert options.findings[-1].kind == "rotation"


def test_lookback_is_bounded():
    many = _sessions(*([CHEST, LEGS] * 10))
    nxt = choose_next(many, today=TODAY)
    assert nxt.session_count == routine_next_pt.NEXT_PT_LOOKBACK
