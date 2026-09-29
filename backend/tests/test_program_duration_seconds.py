"""프로그램 운동 시간의 초 단위(#2221). DB 없이 스키마·요약 규칙만 본다.

트레이너 웹은 시·분·초 세 칸으로 적어 `duration_seconds` 를 보낸다. 분만 있던
동안에는 45초짜리 운동을 적을 수 없었고, 한 시간이 넘으면 90분처럼 환산해야 했다.
"""
from __future__ import annotations

import json

import pytest
from pydantic import ValidationError

from app.schemas.exercise_limits import MAX_EXERCISE_SECONDS
from app.schemas.trainer_api import (
    ProgramDraftExercise,
    ProgramItem,
    ProgramTemplateExercise,
)
from app.services.trainer_service import (
    _program_item_label,
    _program_items,
    _program_seconds_and_type,
    _session_seconds,
    _session_summary,
)


def _draft(**over) -> ProgramDraftExercise:
    return ProgramDraftExercise(**{"id": "e1", "name": "걷기", "type": "유산소", **over})


@pytest.mark.parametrize("model", [ProgramDraftExercise, ProgramItem])
def test_seconds_are_kept_and_minutes_follow(model):
    """초가 기준이고 분은 거기서 반올림한다 — 0 이 아니면 최소 1분."""
    extra = {"id": "e1"} if model is ProgramDraftExercise else {}
    short = model(name="걷기", type="유산소", duration_seconds=45, **extra)
    assert (short.duration_seconds, short.duration) == (45, 1)

    long = model(name="걷기", type="유산소", duration_seconds=5445, **extra)
    assert (long.duration_seconds, long.duration) == (5445, 91)


@pytest.mark.parametrize("model", [ProgramDraftExercise, ProgramItem])
def test_minutes_only_rows_read_as_seconds(model):
    """초가 없는 예전 행·분만 보내는 클라이언트는 분 × 60 으로 읽힌다."""
    extra = {"id": "e1"} if model is ProgramDraftExercise else {}
    old = model(name="걷기", type="유산소", duration=30, **extra)
    assert (old.duration_seconds, old.duration) == (1800, 30)


def test_strength_drops_both_time_units():
    """근력은 세트로 잰다 — 초로 적어 보내도 분·초 둘 다 빈다(#1276)."""
    strength = _draft(type="근력", sets=3, duration_seconds=90)
    assert (strength.duration, strength.duration_seconds) == (None, None)


def test_seconds_have_the_member_log_ceiling():
    """상한은 회원 운동 기록과 같은 10시간이다."""
    assert _draft(duration_seconds=36000).duration == 600
    with pytest.raises(ValidationError):
        _draft(duration_seconds=36001)


def test_stored_program_json_without_seconds_reads_as_seconds():
    """`program_json` 에 초 키가 없는 예전 일정도 초로 읽힌다."""
    old = json.dumps([{"name": "사이클", "type": "유산소", "duration": 15}])
    new = json.dumps(
        [{"name": "걷기", "type": "유산소", "duration": 1, "duration_seconds": 45}]
    )
    assert _program_items(old)[0].duration_seconds == 900
    assert _program_items(new)[0].duration_seconds == 45


def test_summary_adds_seconds_before_folding_into_minutes():
    """초로 더한 뒤 한 번만 분으로 접는다 — 45초 셋을 각각 1분으로 올리면 3분이다."""
    minutes, type_, _ = _session_summary(
        [_draft(id=f"e{i}", duration_seconds=45) for i in range(3)]
    )
    assert (minutes, type_) == (2, "유산소")
    # 배정 행에 남기는 초는 접기 전 값이다(#2521).
    assert _session_seconds([_draft(id=f"e{i}", duration_seconds=45) for i in range(3)]) == 135

    seconds, _ = _program_seconds_and_type(
        [ProgramItem(name="걷기", type="유산소", duration_seconds=45)] * 3
    )
    assert seconds == 135


def test_summary_of_minutes_only_programs_is_unchanged():
    """분만 적힌 프로그램은 예전과 같은 합이다 — 근력은 세트당 3분."""
    minutes, _, _ = _session_summary(
        [
            _draft(id="a", duration=10),
            _draft(id="b", duration=15),
            _draft(id="c", type="근력", sets=3),
        ]
    )
    assert minutes == 34


def test_history_label_stays_in_minutes():
    """이력 한 줄은 분으로 적는다 — `초` 는 버티는 운동의 초로 되읽힌다."""
    item = ProgramItem(name="걷기", type="유산소", duration_seconds=45)
    assert _program_item_label(item) == "걷기 1분"


# ---------------------------------------------------------------------------
# 프로그램 템플릿 (#2521) — 템플릿으로 저장한 운동도 초를 그대로 남긴다.
# ---------------------------------------------------------------------------


def _template(**over) -> ProgramTemplateExercise:
    return ProgramTemplateExercise(**{"name": "버피", "type": "유산소", **over})


def test_a_template_takes_as_long_as_the_editor():
    """편집기가 받는 열 시간짜리 운동도 템플릿으로 저장된다."""
    longest = _template(duration_seconds=MAX_EXERCISE_SECONDS)
    assert longest.minutes == MAX_EXERCISE_SECONDS // 60


def test_a_template_keeps_seconds_and_rounds_minutes():
    """`버피 45초` 가 `1분` 으로, `1시간 30분 15초` 가 `90분` 으로 접히지 않는다."""
    short = _template(duration_seconds=45)
    assert (short.duration_seconds, short.minutes) == (45, 1)

    long = _template(duration_seconds=5415)
    assert (long.duration_seconds, long.minutes) == (5415, 90)


def test_a_minutes_only_template_reads_as_seconds():
    """초가 생기기 전에 저장된 템플릿·분만 보내는 클라이언트는 분 × 60 이다."""
    legacy = _template(minutes=20)
    assert (legacy.duration_seconds, legacy.minutes) == (1200, 20)


def test_seconds_win_over_minutes_in_a_template():
    both = _template(minutes=30, duration_seconds=45)
    assert (both.duration_seconds, both.minutes) == (45, 1)


def test_a_template_seconds_round_trip_through_json():
    """`exercises_json` 에 저장했다가 다시 읽어도 초가 같다."""
    dumped = json.loads(json.dumps(_template(duration_seconds=45).model_dump()))
    again = ProgramTemplateExercise.model_validate(dumped)
    assert (again.duration_seconds, again.minutes) == (45, 1)


@pytest.mark.parametrize(
    "over",
    [
        {},
        {"minutes": 0},
        {"duration_seconds": 0},
        {"duration_seconds": MAX_EXERCISE_SECONDS + 1},
    ],
)
def test_a_template_exercise_needs_a_duration_in_range(over):
    with pytest.raises(ValidationError):
        _template(**over)
