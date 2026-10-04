"""프로그램 운동 시간의 초 단위(#2221). DB 없이 스키마·요약 규칙만 본다.

트레이너 웹은 시·분·초 세 칸으로 적어 `duration_seconds` 를 보낸다. 분만 있던
동안에는 45초짜리 운동을 적을 수 없었고, 한 시간이 넘으면 90분처럼 환산해야 했다.
"""
from __future__ import annotations

import json

import pytest
from pydantic import ValidationError

from app.models.models import TrainerRoutine
from app.schemas.exercise_limits import MAX_EXERCISE_SECONDS
from app.schemas.trainer_api import (
    ProgramDraftExercise,
    ProgramItem,
    ProgramTemplateExercise,
)
from app.services import notification_templates as nt
from app.services.coach.personal_ingest import exercise_text
from app.services.exercise_duration import format_duration
from app.services.trainer._common import (
    _program_items,
    _program_notification_args,
    _program_row_seconds,
    _session_seconds,
    _session_summary,
)
from app.services.trainer.schedule import (
    _personal_row_seconds,
    _program_item_label,
    _program_seconds_and_type,
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


def test_history_label_keeps_seconds():
    """이력 한 줄은 초까지 적는다 — 값은 객체로 함께 남아 문장을 되읽지 않는다. (#2546)"""
    item = ProgramItem(name="걷기", type="유산소", duration_seconds=45)
    assert _program_item_label(item) == "걷기 45초"
    long = ProgramItem(name="사이클", type="유산소", duration_seconds=5415)
    assert _program_item_label(long) == "사이클 1시간 30분 15초"
    assert _program_item_label(ProgramItem(name="런지", type="유산소", duration=20)) == (
        "런지 20분"
    )


@pytest.mark.parametrize(
    ("seconds", "ko", "en"),
    [
        (45, "45초", "45 sec"),
        (60, "1분", "1 min"),
        (1800, "30분", "30 min"),
        (3600, "1시간", "1 hr"),
        (5415, "1시간 30분 15초", "1 hr 30 min 15 sec"),
        (3605, "1시간 5초", "1 hr 5 sec"),
        (0, "0분", "0 min"),
        (-5, "0분", "0 min"),
    ],
)
def test_format_duration_drops_zero_units(seconds, ko, en):
    """0 인 단위는 뺀다 — 회원 앱 `formatDurationParts` 와 같은 규칙. (#2546)"""
    assert format_duration(seconds) == ko
    assert format_duration(seconds, "en") == en


def _routine(exercises: list[dict], minutes: int) -> TrainerRoutine:
    return TrainerRoutine(
        name="코어", minutes=minutes, exercises_json=json.dumps(exercises, ensure_ascii=False)
    )


def test_program_notification_adds_seconds_before_folding():
    """45초 세션 셋은 `2분 15초` 다 — 세션마다 1분으로 올려 `3분` 이 되지 않는다. (#2546)"""
    rows = [
        _routine([{"id": "e1", "name": "버피", "type": "유산소", "duration_seconds": 45}], 1)
        for _ in range(3)
    ]
    args = _program_notification_args(
        "코어", sessions=3, seconds=sum(_program_row_seconds(r) for r in rows), multi=True
    )
    assert (args["seconds"], args["minutes"]) == (135, 2)
    assert nt.render(nt.MEMBER_ROUTINE_PROGRAM, args, "ko") == (
        "새 PT 프로그램이 왔어요", "코어 · 세션 3개 · 2분 15초",
    )
    assert nt.render(nt.MEMBER_ROUTINE_PROGRAM, args, "en") == (
        "New PT program", "코어 · 3 sessions · 2 min 15 sec",
    )


def test_program_row_without_exercises_reads_its_minutes():
    """운동 구성을 읽을 수 없는 줄은 저장된 분으로 읽는다."""
    assert _program_row_seconds(_routine([], 30)) == 1800
    strength = _routine([{"id": "e1", "name": "스쿼트", "type": "근력", "sets": 3}], 9)
    assert _program_row_seconds(strength) == 9 * 60


def test_personal_row_seconds_reads_the_row_itself():
    """PT 에 붙인 개인운동 알림은 줄 하나의 칸으로 시간을 센다. (#3107)

    프로그램 줄 규칙으로 읽으면 운동 구성이 없어 분으로 떨어진다 — 근력만
    붙이면 `개인운동 2개 · 0분`, 45초 운동은 1분이 됐다.
    """
    cardio = TrainerRoutine(name="버피", type="유산소", minutes=1, duration_seconds=45)
    strength = TrainerRoutine(name="스쿼트", type="근력", minutes=0, sets=3)
    legacy = TrainerRoutine(name="걷기", type="유산소", minutes=30)
    assert _personal_row_seconds(cardio) == 45
    assert _personal_row_seconds(strength) == 9 * 60
    assert _personal_row_seconds(legacy) == 30 * 60
    args = _program_notification_args(
        "스쿼트",
        sessions=2,
        seconds=_personal_row_seconds(cardio) + _personal_row_seconds(strength),
        multi=True,
        routine_only=True,
    )
    assert nt.render(nt.MEMBER_ROUTINE_PROGRAM, args, "ko") == (
        "새 개인운동이 왔어요", "개인운동 2개 · 9분 45초",
    )


@pytest.mark.parametrize(
    ("seconds", "expected"), [(45, "유산소 45초"), (None, "유산소 1분"), (5415, "유산소 1시간 30분 15초")]
)
def test_coach_exercise_text_keeps_seconds(seconds, expected):
    """AI 코치가 읽는 기록 글도 초까지 적는다 — 초가 없는 옛 행은 분이다. (#2546)"""
    text = exercise_text(
        date="2026-09-29", exercise_type="cardio", minutes=1 if seconds != 5415 else 90,
        calories=10, intensity="moderate", duration_seconds=seconds,
    )
    assert f" {expected}, " in text


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
