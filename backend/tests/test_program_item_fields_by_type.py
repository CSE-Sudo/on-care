"""운동 한 줄이 자기 유형의 칸만 든다. (#1276)

유형마다 재는 단위가 다르다 — 유산소·스트레칭·기타는 시간, 근력은 세트·횟수·
중량. 그런데 값을 **받는** 자리에는 그 규칙이 없어, 두 칸을 함께 실은 항목이
그대로 저장됐다: 트레이너 상세 일정이 `저강도 유산소 (걷기) 3세트 · 30회` 라고
읽었고, 근력 줄은 세트만 있고 횟수·중량이 빠진 채로 남았다.

스키마 검증은 DB 가 필요 없다. 시드 확인만 DB 를 쓴다.
"""
from __future__ import annotations

from app.services.trainer._common import _amount_label
from app.schemas.trainer_api import (
    ProgramDraftExercise,
    ProgramItem,
    ProgramTemplateExercise,
)


def _tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def test_program_item_drops_sets_from_a_non_strength_item():
    item = ProgramItem(
        name="저강도 유산소 (걷기)", type="유산소",
        duration=30, sets=3, reps=30, weight=12,
    )

    assert item.duration == 30
    assert (item.sets, item.reps, item.weight) == (None, None, None)


def test_program_item_drops_duration_from_a_strength_item():
    """근력의 분은 세트에서 환산한다 — 항목에 적힌 시간은 남기지 않는다."""
    item = ProgramItem(
        name="레그프레스", type="근력", duration=30, sets=3, reps=12, weight=80,
    )

    assert item.duration is None
    assert (item.sets, item.reps, item.weight) == (3, 12, 80)


def test_program_draft_exercise_follows_the_same_rule():
    """초안 편집기와 일정이 같은 계약을 쓴다 — 한쪽만 걸러도 다른 쪽으로 샌다."""
    exercise = ProgramDraftExercise(
        id="e1", name="하체 스트레칭", type="스트레칭",
        duration=10, sets=3, reps=15, weight=5,
    )

    assert exercise.duration == 10
    assert (exercise.sets, exercise.reps, exercise.weight) == (None, None, None)


def test_program_template_exercise_empties_the_strength_fields_with_zero():
    """템플릿은 '적지 않음' 을 0 으로 쓴다 — 비우는 값만 다르고 규칙은 같다."""
    exercise = ProgramTemplateExercise(
        name="코어 스트레칭", minutes=10, type="스트레칭",
        sets=3, reps=15, weight=5,
    )

    assert exercise.minutes == 10
    assert (exercise.sets, exercise.reps, exercise.weight) == (0, 0, 0.0)


def test_seeded_strength_routine_carries_sets_reps_weight(client):
    """근력 배정 시드가 세트·횟수·중량을 든다.

    예전에는 그 값이 이름 안에 문자열로 박혀 있었고(`스쿼트 3세트`) 칸은 비어
    있어, 트레이너 화면이 근력 배정을 `15분` 한 줄로만 읽었다.
    """
    rows = client.get(
        "/v1/trainer/clients/user-jisu/routines", headers={
            "Authorization": f"Bearer {_tok(client)}"
        },
    ).json()

    squat = next(r for r in rows if r["id"] == "seed-routine-user-jisu-1")
    assert squat["name"] == "스쿼트"
    assert (squat["sets"], squat["reps"], squat["weight"]) == (3, 12, 40.0)

    running = next(r for r in rows if r["id"] == "seed-routine-user-jisu-0")
    assert running["type"] == "유산소"
    assert (running["sets"], running["reps"], running["weight"]) == (
        None, None, None,
    )


def test_amount_label_reads_strength_in_sets_reps_weight():
    """배정 알림·배정 수행 이력이 근력을 분으로 적던 자리. (#1276)

    유형 어휘가 둘이다 — 트레이너 배정은 한글, 회원 기록은 영문 코드. 둘 다
    같은 줄로 읽혀야 한다. 맨몸(0kg)은 중량을 적지 않는다(#2533).
    """
    assert _amount_label("근력", minutes=15, sets=3, reps=12, weight=40.0) == (
        "3세트 · 12회 · 40kg"
    )
    assert _amount_label("strength", minutes=12, sets=3, reps=15, weight=0) == (
        "3세트 · 15회"
    )
    assert _amount_label(
        "cardio", minutes=30, sets=None, reps=None, weight=None,
    ) == "30분"


def test_amount_label_falls_back_to_minutes_without_sets():
    """세트가 아예 없는 근력은 그 칸이 생기기 전의 배정뿐이다."""
    assert _amount_label(
        "근력", minutes=15, sets=None, reps=None, weight=None,
    ) == "15분"
