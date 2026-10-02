"""분만 받던 루틴 API 의 초 단위와, 루틴 수정 시 옛 초가 남던 문제. (#2547)

트레이너 쪽 운동 시간은 초(`duration_seconds`)로 바뀌었는데(#2221, #2521) 배정·
제안·승인·수정·칼로리 미리보기는 분만 받았다. 특히 수정은 분만 고치고 초를 그대로
둬서, 초를 먼저 읽는 화면이 `45초` 배정의 분을 5로 고쳐도 계속 `45초` 로 읽었다.

앞쪽은 DB 없이 스키마·규칙만, 뒤쪽은 DB 를 거치는 엔드포인트를 본다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.models.models import TrainerRoutine
from app.schemas.exercise_api import ExerciseCalorieRequest
from app.schemas.trainer_api import (
    RoutineAssignRequest,
    RoutineSuggestionCreateRequest,
    RoutineUpdateRequest,
)
from app.services.trainer._common import _apply_routine_duration, _routine_seconds


# ---- 스키마·규칙 (DB 없음) ----


@pytest.mark.parametrize(
    "model", [RoutineAssignRequest, RoutineSuggestionCreateRequest]
)
def test_seconds_win_and_minutes_are_folded(model):
    req = model(name="버피", type="유산소", minutes=5, duration_seconds=45)
    assert req.duration_seconds == 45
    assert req.minutes == 1

    long = model(name="러닝", type="유산소", duration_seconds=5415)
    assert long.minutes == 90


@pytest.mark.parametrize(
    "model", [RoutineAssignRequest, RoutineSuggestionCreateRequest]
)
def test_minutes_only_is_still_accepted(model):
    req = model(name="러닝", type="유산소", minutes=30)
    assert req.minutes == 30
    assert req.duration_seconds is None


@pytest.mark.parametrize(
    "model", [RoutineAssignRequest, RoutineSuggestionCreateRequest]
)
def test_strength_drops_seconds(model):
    req = model(name="스쿼트", type="근력", sets=3, duration_seconds=45)
    assert req.duration_seconds is None


def test_update_rejects_explicit_null_seconds():
    with pytest.raises(ValidationError):
        RoutineUpdateRequest.model_validate({"duration_seconds": None})


def test_calorie_request_folds_seconds_like_the_save_path():
    req = ExerciseCalorieRequest(type="cardio", name="버피", duration_seconds=45)
    assert req.minutes == 1
    assert (
        ExerciseCalorieRequest(
            type="cardio", name="러닝", duration_seconds=1830
        ).minutes
        == 30
    )
    assert ExerciseCalorieRequest(type="cardio", name="러닝", minutes=20).minutes == 20
    with pytest.raises(ValidationError):
        ExerciseCalorieRequest(type="cardio", name="러닝")


def _row(**kw) -> TrainerRoutine:
    base = {"name": "버피", "type": "유산소", "minutes": 1, "duration_seconds": 45}
    base.update(kw)
    return TrainerRoutine(**base)


def test_minutes_edit_clears_the_old_seconds():
    """고치기 전의 초가 남으면 `_routine_seconds` 가 그 초를 먼저 읽는다."""
    row = _row()
    _apply_routine_duration(row, minutes=5, duration_seconds=None)
    assert row.minutes == 5
    assert row.duration_seconds is None
    assert _routine_seconds(row) == 300


def test_seconds_edit_refolds_minutes():
    row = _row(minutes=30, duration_seconds=None)
    _apply_routine_duration(row, minutes=None, duration_seconds=5415)
    assert row.duration_seconds == 5415
    assert row.minutes == 90
    assert _routine_seconds(row) == 5415


def test_no_duration_in_edit_keeps_it():
    row = _row()
    _apply_routine_duration(row, minutes=None, duration_seconds=None)
    assert (row.minutes, row.duration_seconds) == (1, 45)


def test_edit_to_strength_drops_seconds():
    row = _row(type="근력")
    _apply_routine_duration(row, minutes=None, duration_seconds=None)
    assert row.duration_seconds is None


# ---- 엔드포인트 (DB 필요) ----

MEMBER = "user-jisu"


def _tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def trainer(client):
    """트레이너 토큰과, 테스트가 만든 배정을 끝에 지우는 목록."""
    token = _tok(client)
    created: list[str] = []
    yield token, created
    for rid in created:
        client.delete(
            f"/v1/trainer/clients/{MEMBER}/routines/{rid}", headers=_h(token)
        )


def _assign(client, token: str, created: list[str], **body) -> dict:
    payload = {"name": f"버피 {uuid4().hex[:6]}", "type": "유산소", "reason": ""}
    payload.update(body)
    r = client.post(
        f"/v1/trainer/clients/{MEMBER}/routines", headers=_h(token), json=payload
    )
    assert r.status_code == 201, r.text
    created.append(r.json()["id"])
    return r.json()


def test_assign_with_seconds_keeps_them(client, trainer):
    token, created = trainer
    row = _assign(client, token, created, duration_seconds=45)
    assert row["duration_seconds"] == 45
    assert row["minutes"] == 1


def test_assign_with_minutes_only_is_backward_compatible(client, trainer):
    token, created = trainer
    row = _assign(client, token, created, minutes=20)
    assert row["minutes"] == 20
    assert row["duration_seconds"] == 1200


def test_update_minutes_does_not_leave_old_seconds(client, trainer):
    token, created = trainer
    row = _assign(client, token, created, duration_seconds=45)

    updated = client.put(
        f"/v1/trainer/clients/{MEMBER}/routines/{row['id']}",
        headers=_h(token),
        json={"minutes": 5},
    )

    assert updated.status_code == 200, updated.text
    assert updated.json()["minutes"] == 5
    assert updated.json()["duration_seconds"] == 300
    listed = client.get(
        f"/v1/trainer/clients/{MEMBER}/routines", headers=_h(token)
    ).json()
    assert next(r for r in listed if r["id"] == row["id"])["duration_seconds"] == 300


def test_update_with_seconds_refolds_minutes(client, trainer):
    token, created = trainer
    row = _assign(client, token, created, minutes=30)

    updated = client.put(
        f"/v1/trainer/clients/{MEMBER}/routines/{row['id']}",
        headers=_h(token),
        json={"duration_seconds": 5415},
    )

    assert updated.status_code == 200, updated.text
    assert updated.json()["duration_seconds"] == 5415
    assert updated.json()["minutes"] == 90


def _suggest(client, token: str, created: list[str], **body) -> dict:
    payload = {"name": f"줄넘기 {uuid4().hex[:6]}", "type": "유산소", "reason": ""}
    payload.update(body)
    r = client.post(
        f"/v1/trainer/clients/{MEMBER}/routine-suggestions",
        headers=_h(token),
        json=payload,
    )
    assert r.status_code == 201, r.text
    created.append(r.json()["id"])
    return r.json()


def test_suggestion_with_seconds_keeps_them(client, trainer):
    token, created = trainer
    row = _suggest(client, token, created, duration_seconds=45)
    assert row["duration_seconds"] == 45
    assert row["minutes"] == 1


def test_approve_with_seconds_edit(client, trainer):
    token, created = trainer
    row = _suggest(client, token, created, minutes=10)

    approved = client.post(
        f"/v1/trainer/routine-suggestions/{row['id']}/approve",
        headers=_h(token),
        json={"duration_seconds": 90},
    )

    assert approved.status_code == 200, approved.text
    assert approved.json()["duration_seconds"] == 90
    assert approved.json()["minutes"] == 2


def test_approve_with_minutes_edit_drops_old_seconds(client, trainer):
    token, created = trainer
    row = _suggest(client, token, created, duration_seconds=45)

    approved = client.post(
        f"/v1/trainer/routine-suggestions/{row['id']}/approve",
        headers=_h(token),
        json={"minutes": 5},
    )

    assert approved.status_code == 200, approved.text
    assert approved.json()["minutes"] == 5
    assert approved.json()["duration_seconds"] == 300
