"""부분 수정에서 명시적 null 거절. (#495)

`None` 은 두 가지를 뜻할 수 있다 — 항목을 안 보냈거나, `null` 을 보냈거나.
구분하지 않으면 두 방향으로 어긋난다: NOT NULL 컬럼에 null 이 닿으면 500 이고,
핸들러가 `is not None` 으로 걸러 내면 200 인데 아무것도 안 바뀐다.

규약은 #377 에서 `ScheduleUpdateRequest` 로 처음 생겼지만 그 한 곳에만 있었다.
여기서는 **규약이 적용된 스키마 전부**와, 의도적으로 제외한 한 곳을 함께 고정한다.

`TrainerSlotUpdate`(#478)는 이 목록에 없다 — 같은 규약을 자체 구현하고 있고,
"빈 요청 거절"·"타임존 필수"라는 더 엄격한 규칙을 함께 갖는다. 공용 베이스로
옮기면 그 규칙까지 건드려야 하므로 그대로 둔다.

스키마 단위 검증은 DB 없이 돌고, 엔드포인트 확인만 DB 를 쓴다.
"""
from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.schemas.diet_api import DietEntryUpdate
from app.schemas.trainer_api import (
    ScheduleUpdateRequest,
    TrainerMeUpdate,
    TrainerNotificationSettingsUpdate,
)
from app.schemas.user import (
    HealthGoalsUpdate,
    MemberNotificationSettingsUpdate,
    ProfileUpdate,
)

#: (스키마, null 을 보낼 필드, 정상값). 규약이 적용된 전부.
_REJECTING = [
    (DietEntryUpdate, "meal_type", "lunch"),
    (ScheduleUpdateRequest, "client_name", "김민수"),
    (TrainerMeUpdate, "phone", "010-0000-0000"),
    (TrainerNotificationSettingsUpdate, "notify_new_message", False),
    (MemberNotificationSettingsUpdate, "trainer_message", False),
    (ProfileUpdate, "name", "김민수"),
]


@pytest.mark.parametrize(
    ("schema", "field", "value"),
    _REJECTING,
    ids=[schema.__name__ for schema, _, _ in _REJECTING],
)
def test_explicit_null_is_rejected(schema, field, value):
    with pytest.raises(ValidationError):
        schema(**{field: None})


@pytest.mark.parametrize(
    ("schema", "field", "value"),
    _REJECTING,
    ids=[schema.__name__ for schema, _, _ in _REJECTING],
)
def test_a_real_value_still_passes(schema, field, value):
    assert getattr(schema(**{field: value}), field) == value


@pytest.mark.parametrize(
    ("schema", "field", "value"),
    _REJECTING,
    ids=[schema.__name__ for schema, _, _ in _REJECTING],
)
def test_omitted_fields_still_mean_no_change(schema, field, value):
    """누락은 여전히 '변경 없음' — null 거절이 부분 수정을 망가뜨리면 안 된다."""
    payload = schema()

    assert payload.model_fields_set == set()
    assert payload.model_dump(exclude_unset=True) == {}


def test_schedule_keeps_member_id_nullable():
    """`member_id` 의 null 은 '배정 해제'라 규약의 예외다(#377)."""
    payload = ScheduleUpdateRequest(member_id=None)

    assert payload.member_id is None
    assert "member_id" in payload.model_fields_set


def test_health_goals_still_accepts_null_to_clear_a_goal():
    """건강 목표는 컬럼이 nullable 이고 null 이 '목표 해제'로 동작한다.

    규약은 NOT NULL 컬럼을 지키려는 것이므로 여기에는 해당하지 않는다. 적용하면
    목표를 지울 방법이 사라진다(#495).
    """
    payload = HealthGoalsUpdate(daily_calories=None)

    assert payload.daily_calories is None
    assert payload.model_dump(exclude_unset=True) == {"daily_calories": None}
