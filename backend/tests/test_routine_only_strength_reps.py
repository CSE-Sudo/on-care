"""`개인운동만` 으로 보낸 근력 운동의 횟수가 남는다.

트레이너 웹은 개인운동을 세션 운동 모양으로 옮기며 빈 칸을 0 으로 채웠다 —
`hold_seconds: 0` 이다. 서버는 `hold_seconds` 가 `None` 이 아니면 버티는 운동으로
보고 횟수를 지웠으므로(#1969), 일반 근력 운동도 `reps` 가 빠진 채 저장됐고 회원은
`스쿼트 3세트 · 12회` 를 `스쿼트 3세트` 로 받았다.

이제 0 이하의 초는 "버티지 않음" 이다 — 초를 `None` 으로 접고 횟수는 남긴다.
앞의 테스트는 DB 없이, 마지막 테스트는 DB 가 있어야 돈다.
"""
from __future__ import annotations

import json

import pytest
from sqlalchemy import or_, select

from app.models.models import TrainerRoutine
from app.schemas.trainer_api import ProgramDraftExercise, ProgramItem

MEMBER = "user-jisu"
_PREFIX = "횟수 유지 테스트"


@pytest.mark.parametrize("model", [ProgramDraftExercise, ProgramItem])
def test_zero_hold_seconds_keeps_reps(model):
    """`hold_seconds=0` 은 버티기가 아니다 — 횟수가 그대로 남는다."""
    extra = {"id": "ex-1"} if model is ProgramDraftExercise else {}
    item = model(
        name="스쿼트", type="근력", sets=3, reps=12, hold_seconds=0, **extra
    )
    assert item.reps == 12
    assert item.hold_seconds is None
    assert item.sets == 3


@pytest.mark.parametrize("model", [ProgramDraftExercise, ProgramItem])
def test_positive_hold_seconds_still_clears_reps(model):
    """버티는 운동은 지금처럼 초가 맞고 횟수가 빈다(#1969)."""
    extra = {"id": "ex-1"} if model is ProgramDraftExercise else {}
    item = model(
        name="플랭크", type="근력", sets=3, reps=10, hold_seconds=60, **extra
    )
    assert item.reps is None
    assert item.hold_seconds == 60


def test_missing_hold_seconds_keeps_reps():
    """초를 아예 보내지 않은 근력 운동도 횟수가 남는다."""
    item = ProgramDraftExercise(
        id="ex-1", name="런지", type="근력", sets=3, reps=10
    )
    assert item.reps == 10
    assert item.hold_seconds is None


def test_null_fields_are_accepted_for_strength():
    """정하지 않은 칸은 `null` 로 와도 된다 — 트레이너 웹의 새 본문 모양이다."""
    item = ProgramDraftExercise.model_validate(
        {
            "id": "personal-0",
            "name": "스쿼트",
            "type": "근력",
            "duration": 0,
            "duration_seconds": None,
            "sets": 3,
            "reps": 12,
            "hold_seconds": None,
            "weight": None,
        }
    )
    assert (item.sets, item.reps, item.hold_seconds, item.weight) == (
        3,
        12,
        None,
        None,
    )


def test_zero_hold_seconds_on_cardio_is_still_dropped():
    """근력이 아닌 유형은 지금처럼 세트·횟수·초·중량을 모두 비운다."""
    item = ProgramDraftExercise(
        id="ex-1", name="걷기", type="유산소", duration=30, hold_seconds=0, reps=5
    )
    assert item.reps is None
    assert item.hold_seconds is None


def _tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _cleanup(db_session) -> None:
    for routine in db_session.scalars(
        select(TrainerRoutine).where(
            TrainerRoutine.member_id == MEMBER,
            or_(
                TrainerRoutine.name.like(f"{_PREFIX}%"),
                TrainerRoutine.program_name.like(f"{_PREFIX}%"),
            ),
        )
    ).all():
        db_session.delete(routine)
    db_session.commit()


def test_routine_only_delivery_keeps_strength_reps(client, db_session):
    """`개인운동만` 배정으로 저장된 `exercises_json` 에 횟수가 남는다."""
    token = _tok(client)
    _cleanup(db_session)
    try:
        r = client.post(
            f"/v1/trainer/clients/{MEMBER}/program",
            json={
                "name": f"{_PREFIX} 이번 주 개인운동",
                "sessions": [
                    {
                        "id": "routine-only-0",
                        "name": f"{_PREFIX} 스쿼트",
                        "exercises": [
                            # 고치기 전 트레이너 웹이 보내던 모양 그대로다.
                            {
                                "id": "personal-0",
                                "name": f"{_PREFIX} 스쿼트",
                                "type": "근력",
                                "duration": 0,
                                "duration_seconds": None,
                                "sets": 3,
                                "reps": 12,
                                "hold_seconds": 0,
                                "weight": 0,
                                "source": "trainer",
                            },
                        ],
                    },
                    {
                        "id": "routine-only-1",
                        "name": f"{_PREFIX} 플랭크",
                        "exercises": [
                            {
                                "id": "personal-1",
                                "name": f"{_PREFIX} 플랭크",
                                "type": "근력",
                                "duration": 0,
                                "sets": 3,
                                "reps": None,
                                "hold_seconds": 60,
                                "weight": None,
                                "source": "trainer",
                            },
                        ],
                    },
                ],
                "delivery_kind": "routine_only",
                "active_days": 7,
                "client_request_id": "req-routine-only-reps",
            },
            headers={"Authorization": f"Bearer {token}"},
        )
        assert r.status_code == 201, r.text

        db_session.expire_all()
        rows = db_session.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.member_id == MEMBER,
                or_(
                    TrainerRoutine.name.like(f"{_PREFIX}%"),
                    TrainerRoutine.program_name.like(f"{_PREFIX}%"),
                ),
            )
        ).all()
        by_name = {
            ex["name"]: ex
            for row in rows
            for ex in json.loads(row.exercises_json or "[]")
        }
        squat = by_name[f"{_PREFIX} 스쿼트"]
        assert squat["reps"] == 12
        assert squat.get("hold_seconds") is None
        plank = by_name[f"{_PREFIX} 플랭크"]
        assert plank["hold_seconds"] == 60
        assert plank.get("reps") is None
    finally:
        _cleanup(db_session)
