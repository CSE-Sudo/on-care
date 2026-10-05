"""회원에게 내려가는 버티기 운동 계약 — `hold_seconds` 가 있고 `reps` 가 빈다. (#3138)

회원 앱은 이 계약을 믿고 `hold_seconds` 가 있으면 횟수 자리에 `N초` 를 적는다.
세 응답 모양(개인운동 `RoutineOut`, 그 운동 구성 `ProgramDraftExercise`, PT
수업 프로그램 `ProgramItem`)이 모두 같은 규칙이어야 회원이 어느 화면에서 보든
`3세트 · 60초` 로 읽는다. DB 가 필요 없는 스키마 단위 확인이다.
"""
from __future__ import annotations

from app.schemas.trainer_api import ProgramDraftExercise, ProgramItem, RoutineOut


def _routine(**overrides) -> RoutineOut:
    base = {
        "id": "r-plank",
        "name": "플랭크",
        "minutes": 6,
        "type": "근력",
        "reason": "",
        "source": "trainer",
    }
    base.update(overrides)
    return RoutineOut(**base)


# ---- ProgramItem (PT 수업 프로그램 한 줄) ----


def test_program_item_hold_keeps_seconds_and_clears_reps():
    item = ProgramItem(name="플랭크", type="근력", sets=3, reps=10, hold_seconds=60)
    dumped = item.model_dump()

    assert dumped["hold_seconds"] == 60
    # 한 세트를 두 단위로 적지 않는다(#1969) — 초가 있으면 횟수가 빈다.
    assert dumped["reps"] is None
    assert dumped["sets"] == 3


def test_program_item_reps_only_stays_reps():
    item = ProgramItem(name="스쿼트", type="근력", sets=4, reps=12, weight=40)
    dumped = item.model_dump()

    assert dumped["reps"] == 12
    assert dumped["hold_seconds"] is None


def test_program_item_hold_dropped_for_non_strength():
    # 유산소·스트레칭은 시간으로 잰다 — 버티는 초 칸이 남으면 회원 앱이
    # `30분 · 60초` 처럼 두 단위로 읽는다.
    item = ProgramItem(name="걷기", type="유산소", duration=30, hold_seconds=60)
    dumped = item.model_dump()

    assert dumped["hold_seconds"] is None
    assert dumped["duration_seconds"] == 1800


def test_program_item_legacy_row_without_hold_reads():
    # 이 칸이 생기기 전의 행은 키가 없다 — 그대로 읽히고 비어 있다.
    item = ProgramItem.model_validate({"name": "벤치프레스", "sets": 4, "reps": "10회"})

    assert item.hold_seconds is None
    assert item.reps == 10


# ---- ProgramDraftExercise (개인운동·프로그램 세션의 운동 구성) ----


def test_draft_exercise_hold_keeps_seconds_and_clears_reps():
    exercise = ProgramDraftExercise(
        id="ex-1", name="플랭크", type="근력", sets=3, reps=12, hold_seconds=45
    )
    dumped = exercise.model_dump()

    assert dumped["hold_seconds"] == 45
    assert dumped["reps"] is None


def test_draft_exercise_string_hold_is_loosely_parsed():
    # 옛 편집기가 `"60초"` 같은 문자열로 보낸 값도 숫자만 남긴다.
    exercise = ProgramDraftExercise.model_validate(
        {"id": "ex-2", "name": "월싯", "type": "근력", "sets": 3, "hold_seconds": "60초"}
    )

    assert exercise.hold_seconds == 60
    assert exercise.reps is None


# ---- RoutineOut (회원 앱 `/me/coach/routines` 한 건) ----


def test_routine_out_serializes_hold_seconds_for_member():
    routine = _routine(sets=3, reps=None, hold_seconds=60, weight=0)
    dumped = routine.model_dump(mode="json")

    assert dumped["hold_seconds"] == 60
    assert dumped["reps"] is None
    assert dumped["sets"] == 3


def test_routine_out_exercises_carry_hold_seconds():
    routine = _routine(
        program_name="코어 4주",
        session_name="세션 A",
        exercises=[
            ProgramDraftExercise(
                id="ex-1", name="플랭크", type="근력", sets=3, hold_seconds=60
            ),
            ProgramDraftExercise(
                id="ex-2", name="스쿼트", type="근력", sets=4, reps=12, weight=40
            ),
        ],
    )
    exercises = routine.model_dump(mode="json")["exercises"]

    assert exercises[0]["hold_seconds"] == 60
    assert exercises[0]["reps"] is None
    assert exercises[1]["hold_seconds"] is None
    assert exercises[1]["reps"] == 12


def test_routine_out_without_hold_defaults_to_none():
    # 버티지 않는 개인운동과 이 칸을 모르는 옛 행은 비어 있다 — 회원 앱은
    # 그때 지금처럼 횟수를 적는다.
    dumped = _routine(sets=3, reps=15, weight=0).model_dump(mode="json")

    assert "hold_seconds" in dumped
    assert dumped["hold_seconds"] is None
    assert dumped["reps"] == 15
