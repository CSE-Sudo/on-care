"""자유 입력 글자 수 상한 등급 — 칸마다 정한 등급을 쓰는가. (#2618)

DB 없이 스키마만 본다. 앱 입력칸(`AppTextLimits`)도 같은 숫자를 쓰므로, 여기
값이 바뀌면 두 앱의 `maxLength` 도 함께 바꿔야 한다.
"""
from __future__ import annotations

import pytest
from pydantic import BaseModel, ValidationError

from app.schemas.consultation_api import ConsultationCreate, ConsultationDecision
from app.schemas.text_limits import (
    TEXT_ENTRY_MAX,
    TEXT_LINE_MAX,
    TEXT_LONG_MAX,
    TEXT_NAME_MAX,
)
from app.schemas.trainer_api import (
    ChatSendRequest,
    MemberHealthProfileUpdate,
    MemberWeeklyFeedbackSaveRequest,
    ReportFeedbackSaveRequest,
    ReportSendRequest,
    ScheduleCompleteRequest,
    ScheduleCreateRequest,
    ScheduleRecurringRequest,
    ScheduleUpdateRequest,
    TrainerClientInviteCreate,
    TrainerMeUpdate,
    TrainerProgramDraftCreate,
    TrainerProgramDraftUpdate,
)
from app.schemas.user import HealthGoalsUpdate, OnboardingRequest


def test_grades_are_ordered():
    assert (TEXT_NAME_MAX, TEXT_LINE_MAX, TEXT_ENTRY_MAX, TEXT_LONG_MAX) == (
        100,
        200,
        500,
        1000,
    )


def _max_length(model: type[BaseModel], field: str) -> int:
    prop = model.model_json_schema()["properties"][field]
    shapes = prop.get("anyOf", [prop])
    lengths = [s["maxLength"] for s in shapes if "maxLength" in s]
    assert len(lengths) == 1, (model.__name__, field, prop)
    return lengths[0]


@pytest.mark.parametrize(
    ("model", "field", "limit"),
    [
        # PT 세션 피드백 — 값은 그대로, 등급 이름만 붙었다.
        (ScheduleCreateRequest, "note", TEXT_ENTRY_MAX),
        (ScheduleRecurringRequest, "note", TEXT_ENTRY_MAX),
        (ScheduleUpdateRequest, "note", TEXT_ENTRY_MAX),
        (ScheduleCompleteRequest, "note", TEXT_ENTRY_MAX),
        # 긴 글
        (ReportFeedbackSaveRequest, "body", TEXT_LONG_MAX),
        (ReportSendRequest, "message", TEXT_LONG_MAX),
        (ChatSendRequest, "text", TEXT_LONG_MAX),
        (ConsultationCreate, "message", TEXT_LONG_MAX),
        # 목표가 `기타` 면 문의 글이 그대로 여기에도 실린다.
        (ConsultationCreate, "health_purpose_detail", TEXT_LONG_MAX),
        # 한 줄
        (ConsultationDecision, "note", TEXT_LINE_MAX),
        (MemberWeeklyFeedbackSaveRequest, "note", TEXT_LINE_MAX),
        (TrainerClientInviteCreate, "message", TEXT_LINE_MAX),
        # 기록 한 건
        (TrainerMeUpdate, "intro", TEXT_ENTRY_MAX),
        (TrainerProgramDraftCreate, "memo", TEXT_ENTRY_MAX),
        (TrainerProgramDraftUpdate, "memo", TEXT_ENTRY_MAX),
    ],
    ids=lambda v: v.__name__ if isinstance(v, type) else str(v),
)
def test_field_uses_its_grade(model, field, limit):
    assert _max_length(model, field) == limit


def test_report_draft_fits_in_a_report_message():
    """저장은 됐는데 보낼 수 없는 길이가 생기면 안 된다."""
    assert _max_length(ReportFeedbackSaveRequest, "body") <= _max_length(
        ReportSendRequest, "message"
    )


# ---- 건강상태·주의사항(`conditions` 의 트레이너 글) ----


def test_trainer_notes_up_to_the_limit_are_accepted_with_focus():
    """목표 칩은 글자 수에 넣지 않는다 — 트레이너가 보는 칸은 글뿐이다."""
    notes = "가" * TEXT_ENTRY_MAX
    saved = MemberHealthProfileUpdate(conditions=f"체중 감량, 재활, {notes}")
    assert saved.conditions == f"체중 감량, 재활, {notes}"


def test_trainer_notes_over_the_limit_are_refused():
    with pytest.raises(ValidationError):
        MemberHealthProfileUpdate(conditions="가" * (TEXT_ENTRY_MAX + 1))


def test_comma_spacing_does_not_count_against_the_trainer():
    """저장 형태는 `, ` 로 잇지만, 입력칸에 적은 글자 수보다 길게 세지 않는다."""
    # 같은 조각은 하나로 합쳐지므로 조각마다 다르게 둔다.
    typed = ",".join(f"{i}" + "가" * 98 for i in range(5))  # 99*5 + 4 = 499자
    assert len(typed) <= TEXT_ENTRY_MAX
    saved = MemberHealthProfileUpdate(conditions=typed)
    assert saved.conditions is not None
    assert len(saved.conditions) > TEXT_ENTRY_MAX  # 저장 형태는 더 길다


@pytest.mark.parametrize("schema", [HealthGoalsUpdate, OnboardingRequest])
def test_member_paths_use_the_same_notes_limit(schema):
    """회원도 온보딩·MY 에서 주의사항을 적는다 — 트레이너 경로와 같은 상한이다(#2619)."""
    assert schema(conditions="재활, " + "가" * TEXT_ENTRY_MAX).conditions
    with pytest.raises(ValidationError):
        schema(conditions="재활, " + "가" * (TEXT_ENTRY_MAX + 1))
