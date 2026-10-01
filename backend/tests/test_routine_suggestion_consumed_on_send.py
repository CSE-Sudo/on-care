"""전송에 실려 나간 AI 개인운동 제안의 종결. (#2747) 앞쪽은 DB 없음, 뒤쪽은 DB 필요.

프로그램 만들기 위저드의 개인운동 단계는 대기 중 AI 제안으로 채워진다. 그 제안을
`개인운동만`(`POST .../program`)이나 PT 와 함께(`POST .../program-schedule`)
보내거나, 이미 있는 PT 에 붙여도(`PUT /trainer/schedule/{id}/routines`) 서버의 제안은 대기로 남아 있었다 — 다음 위저드가 보낸 제안을 다시 채우고,
대기가 쌓여 백로그 한도(`MAX_PENDING_BACKLOG`)에 걸리면 새 제안 준비가 멈췄다.

전송 본문의 `suggestion_ids` 로 그 제안을 배정과 **같은 트랜잭션**에서 닫는다.
"""
from __future__ import annotations

from datetime import timedelta
from uuid import uuid4

import pytest
from pydantic import ValidationError
from sqlalchemy import or_, select

from app.core import clock
from app.models.models import TrainerRoutine, TrainerSchedule
from app.schemas.trainer_api import (
    ProgramAssignRequest,
    ProgramScheduleRequest,
    ScheduleRoutineUpdateRequest,
)
from app.services import routine_suggestion_service as suggestions
from app.services import trainer_service

MEMBER = "user-jisu"
#: 같은 트레이너의 다른 담당 회원 — 남의 회원 제안 id 를 섞어 보낸다.
OTHER_MEMBER = "user-7d4e9a2c5f18"
TRAINER = "trainer-demo"
_PROGRAM_URL = f"/v1/trainer/clients/{MEMBER}/program"
_SCHEDULE_URL = f"/v1/trainer/clients/{MEMBER}/program-schedule"
_PREFIX = "제안 종결 테스트"


# ---- 스키마 (DB 없음) ----


def _session() -> dict:
    return {
        "id": "s1",
        "name": "걷기",
        "exercises": [{"id": "e1", "name": "걷기", "duration": 30}],
    }


@pytest.mark.parametrize("model", [ProgramAssignRequest, ProgramScheduleRequest])
def test_suggestion_ids_default_to_empty(model):
    """옛 앱은 이 필드를 모른다 — 빠져도 받아야 한다."""
    body = {"name": "이번 주", "sessions": [_session()]}
    if model is ProgramScheduleRequest:
        body.update(
            date=(clock.today() + timedelta(days=1)).isoformat(),
            time="10:00",
            duration_minutes=50,
        )
    assert model.model_validate(body).suggestion_ids == []


def test_schedule_routine_update_takes_suggestion_ids():
    """이미 있는 PT 에 붙이는 길도 같은 필드를 받고, 없어도 받는다."""
    item = {"name": "걷기", "minutes": 20, "type": "유산소"}
    assert (
        ScheduleRoutineUpdateRequest.model_validate(
            {"personal_routines": [item]}
        ).suggestion_ids
        == []
    )
    assert ScheduleRoutineUpdateRequest.model_validate(
        {"personal_routines": [item], "suggestion_ids": ["a"]}
    ).suggestion_ids == ["a"]


def test_suggestion_ids_are_kept_in_order():
    req = ProgramAssignRequest.model_validate(
        {"name": "이번 주", "sessions": [_session()], "suggestion_ids": ["a", "b"]}
    )
    assert req.suggestion_ids == ["a", "b"]


def test_blank_suggestion_id_is_rejected():
    with pytest.raises(ValidationError):
        ProgramAssignRequest.model_validate(
            {"name": "이번 주", "sessions": [_session()], "suggestion_ids": [""]}
        )


def test_consumed_is_a_routine_status_of_its_own():
    """`approved` 면 회원 목록에 두 벌, `dismissed` 면 '추천 안 함' 과 섞인다."""
    assert trainer_service.ROUTINE_CONSUMED in trainer_service.ROUTINE_STATUSES
    assert trainer_service.ROUTINE_CONSUMED not in {
        trainer_service.ROUTINE_APPROVED,
        trainer_service.ROUTINE_PENDING,
        trainer_service.ROUTINE_DISMISSED,
        trainer_service.ROUTINE_SCHEDULED,
    }


# ---- 엔드포인트 (DB 필요) ----


def _tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _member_tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "jisu@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _pending(db_session, member_id: str = MEMBER) -> str:
    """대기 중 AI 제안 하나를 직접 넣고 id 를 준다.

    준비 키(`sug-`)와 다른 멱등키를 써, 이 파일의 제안이 그날 준비 묶음과
    섞이지 않게 한다.
    """
    row_id = f"cons-{uuid4().hex[:10]}"
    db_session.add(
        TrainerRoutine(
            id=row_id,
            trainer_id=TRAINER,
            member_id=member_id,
            name=f"{_PREFIX} 걷기",
            minutes=20,
            type="유산소",
            reason="",
            source="ai",
            status=trainer_service.ROUTINE_PENDING,
            client_request_id=row_id,
        )
    )
    db_session.commit()
    return row_id


def _status(db_session, row_id: str) -> str:
    db_session.expire_all()
    row = db_session.get(TrainerRoutine, row_id)
    assert row is not None
    return row.status


@pytest.fixture()
def clean(db_session):
    made_schedules: list[str] = []
    yield made_schedules
    db_session.rollback()
    for sid in made_schedules:
        row = db_session.get(TrainerSchedule, sid)
        if row is not None:
            db_session.delete(row)
    for row in db_session.scalars(
        select(TrainerRoutine).where(
            or_(
                TrainerRoutine.id.like("cons-%"),
                TrainerRoutine.name.like(f"{_PREFIX}%"),
                TrainerRoutine.program_name.like(f"{_PREFIX}%"),
            )
        )
    ).all():
        db_session.delete(row)
    db_session.commit()


def _routine_only(request_id: str, suggestion_ids: list[str]) -> dict:
    return {
        "name": f"{_PREFIX} 이번 주 개인운동",
        "sessions": [
            {
                "id": "s-walk",
                "name": f"{_PREFIX} 걷기",
                "exercises": [
                    {"id": "e-walk", "name": f"{_PREFIX} 걷기", "duration": 20}
                ],
            }
        ],
        "delivery_kind": "routine_only",
        "active_days": 7,
        "client_request_id": request_id,
        "suggestion_ids": suggestion_ids,
    }


def _review_ids(client, token: str, member_id: str = MEMBER) -> set[str]:
    res = client.get(
        f"/v1/trainer/clients/{member_id}/routine-suggestions", headers=_h(token)
    )
    assert res.status_code == 200, res.text
    return {row["id"] for row in res.json()}


def test_routine_only_send_closes_the_suggestion(client, db_session, clean):
    token = _tok(client)
    sid = _pending(db_session)
    assert sid in _review_ids(client, token)

    r = client.post(
        _PROGRAM_URL,
        json=_routine_only(f"cons-{uuid4().hex[:8]}", [sid]),
        headers=_h(token),
    )

    assert r.status_code == 201, r.text
    assert _status(db_session, sid) == trainer_service.ROUTINE_CONSUMED
    # 다시 연 위저드가 같은 제안을 채우지 않는다.
    assert sid not in _review_ids(client, token)


def test_consumed_suggestion_does_not_reach_the_member_twice(
    client, db_session, clean
):
    """회원이 받는 것은 전송이 만든 배정 한 건이다 — 제안 행은 회원 목록에 없다."""
    token = _tok(client)
    sid = _pending(db_session)

    sent = client.post(
        _PROGRAM_URL,
        json=_routine_only(f"cons-{uuid4().hex[:8]}", [sid]),
        headers=_h(token),
    )
    assert sent.status_code == 201, sent.text

    mine = client.get("/v1/me/coach/routines", headers=_h(_member_tok(client)))
    assert mine.status_code == 200, mine.text
    ids = {row["id"] for row in mine.json()}
    assert sid not in ids
    assert {row["id"] for row in sent.json()} <= ids


def test_failed_send_keeps_the_suggestion_pending(client, db_session, clean):
    token = _tok(client)
    sid = _pending(db_session)
    body = _routine_only(f"cons-{uuid4().hex[:8]}", [sid])
    body["sessions"][0]["exercises"] = []

    r = client.post(_PROGRAM_URL, json=body, headers=_h(token))

    assert r.status_code == 400, r.text
    assert _status(db_session, sid) == trainer_service.ROUTINE_PENDING
    assert sid in _review_ids(client, token)


def test_other_members_suggestion_id_is_ignored(client, db_session, clean):
    token = _tok(client)
    mine = _pending(db_session)
    theirs = _pending(db_session, OTHER_MEMBER)

    r = client.post(
        _PROGRAM_URL,
        json=_routine_only(f"cons-{uuid4().hex[:8]}", [mine, theirs, "nope"]),
        headers=_h(token),
    )

    assert r.status_code == 201, r.text
    assert _status(db_session, mine) == trainer_service.ROUTINE_CONSUMED
    # 다른 회원 제안은 그 회원의 검토 목록에 그대로 남는다.
    assert _status(db_session, theirs) == trainer_service.ROUTINE_PENDING


def test_already_reviewed_suggestion_is_left_alone(client, db_session, clean):
    """다른 창에서 먼저 거절한 제안 id 가 섞여 와도 전송은 막히지 않는다."""
    token = _tok(client)
    sid = _pending(db_session)
    dismissed = client.post(
        f"/v1/trainer/routine-suggestions/{sid}/dismiss", headers=_h(token)
    )
    assert dismissed.status_code == 200, dismissed.text

    r = client.post(
        _PROGRAM_URL,
        json=_routine_only(f"cons-{uuid4().hex[:8]}", [sid]),
        headers=_h(token),
    )

    assert r.status_code == 201, r.text
    assert _status(db_session, sid) == trainer_service.ROUTINE_DISMISSED


def test_pt_with_routine_send_closes_the_suggestion(client, db_session, clean):
    token = _tok(client)
    sid = _pending(db_session)
    day = (clock.today() + timedelta(days=87)).isoformat()

    r = client.post(
        _SCHEDULE_URL,
        json={
            "name": f"{_PREFIX} PT",
            "sessions": [
                {
                    "id": "s1",
                    "name": "A",
                    "exercises": [
                        {
                            "id": "e1",
                            "name": f"{_PREFIX} 스쿼트",
                            "type": "근력",
                            "sets": 3,
                            "reps": 10,
                        }
                    ],
                }
            ],
            "date": day,
            "time": "06:10",
            "duration_minutes": 30,
            "client_name": "이지수",
            "client_request_id": f"cons-{uuid4().hex[:8]}",
            "personal_routines": [
                {
                    "name": f"{_PREFIX} 걷기",
                    "minutes": 20,
                    "type": "유산소",
                    "source": "ai",
                }
            ],
            "suggestion_ids": [sid],
        },
        headers=_h(token),
    )

    assert r.status_code == 201, r.text
    clean.append(r.json()["session"]["id"])
    assert _status(db_session, sid) == trainer_service.ROUTINE_CONSUMED
    assert sid not in _review_ids(client, token)


def test_pt_with_routine_failure_keeps_the_suggestion(client, db_session, clean):
    """지난 날짜로 등록하면 거절된다 — 제안도 그대로 대기다."""
    token = _tok(client)
    sid = _pending(db_session)

    r = client.post(
        _SCHEDULE_URL,
        json={
            "name": f"{_PREFIX} PT",
            "sessions": [_session()],
            "date": (clock.today() - timedelta(days=1)).isoformat(),
            "time": "06:10",
            "duration_minutes": 30,
            "suggestion_ids": [sid],
        },
        headers=_h(token),
    )

    assert r.status_code == 422, r.text
    assert _status(db_session, sid) == trainer_service.ROUTINE_PENDING


def test_sending_frees_the_backlog_for_new_suggestions(client, db_session, clean):
    """보낸 제안이 대기로 남으면 백로그 한도에 걸려 새 제안이 끊긴다."""
    token = _tok(client)
    # 오늘 준비 묶음을 지워 '아직 준비 안 됨' 에서 시작한다.
    for row in db_session.scalars(
        select(TrainerRoutine).where(
            TrainerRoutine.member_id == MEMBER,
            TrainerRoutine.client_request_id.like("sug-%"),
        )
    ).all():
        db_session.delete(row)
    db_session.commit()
    # 다른 파일이 남긴 대기 제안이 있으면 그것까지 닫아야 해 이 검증이 남의
    # 데이터를 바꾼다 — 그때는 건너뛴다.
    already = len(
        db_session.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.trainer_id == TRAINER,
                TrainerRoutine.member_id == MEMBER,
                TrainerRoutine.status == trainer_service.ROUTINE_PENDING,
            )
        ).all()
    )
    if already:
        pytest.skip("다른 대기 제안이 남아 있다")
    backlog = [_pending(db_session) for _ in range(suggestions.MAX_PENDING_BACKLOG)]
    # 한도가 차 있어 오늘 후보가 준비되지 않는다.
    assert not any(i.startswith("sug-") for i in _review_ids(client, token))

    r = client.post(
        _PROGRAM_URL,
        json=_routine_only(f"cons-{uuid4().hex[:8]}", backlog),
        headers=_h(token),
    )
    assert r.status_code == 201, r.text

    for sid in backlog:
        assert _status(db_session, sid) == trainer_service.ROUTINE_CONSUMED
    # 한도가 비었으니 오늘 후보가 준비된다(신호가 있는 시드 회원).
    assert any(i.startswith("sug-") for i in _review_ids(client, token))
    for row in db_session.scalars(
        select(TrainerRoutine).where(
            TrainerRoutine.member_id == MEMBER,
            TrainerRoutine.client_request_id.like("sug-%"),
        )
    ).all():
        db_session.delete(row)
    db_session.commit()


# ---- 이미 있는 PT 에 붙이기 (`PUT /trainer/schedule/{id}/routines`) ----


def _walk(name: str = "걷기") -> dict:
    return {
        "name": f"{_PREFIX} {name}",
        "minutes": 20,
        "type": "유산소",
        "source": "ai",
    }


def _pt(client, token: str, clean: list[str], days: int, personal: list[dict]) -> str:
    """먼 날짜에 PT 를 하나 잡고 일정 id 를 준다."""
    r = client.post(
        _SCHEDULE_URL,
        json={
            "name": f"{_PREFIX} PT",
            "sessions": [
                {
                    "id": "s1",
                    "name": "A",
                    "exercises": [
                        {
                            "id": "e1",
                            "name": f"{_PREFIX} 스쿼트",
                            "type": "근력",
                            "sets": 3,
                            "reps": 10,
                        }
                    ],
                }
            ],
            "date": (clock.today() + timedelta(days=days)).isoformat(),
            "time": "06:10",
            "duration_minutes": 30,
            "client_name": "이지수",
            "client_request_id": f"cons-{uuid4().hex[:8]}",
            "personal_routines": personal,
        },
        headers=_h(token),
    )
    assert r.status_code == 201, r.text
    session_id = r.json()["session"]["id"]
    clean.append(session_id)
    return session_id


def test_first_attach_to_existing_pt_closes_the_suggestion(client, db_session, clean):
    """개인운동 없이 잡힌 PT 에 위저드의 개인운동을 처음 붙인다(#2280)."""
    token = _tok(client)
    session_id = _pt(client, token, clean, 88, [])
    sid = _pending(db_session)

    r = client.put(
        f"/v1/trainer/schedule/{session_id}/routines",
        json={"personal_routines": [_walk()], "suggestion_ids": [sid]},
        headers=_h(token),
    )

    assert r.status_code == 200, r.text
    assert _status(db_session, sid) == trainer_service.ROUTINE_CONSUMED
    assert sid not in _review_ids(client, token)


def test_rewriting_attached_routines_closes_the_suggestion(client, db_session, clean):
    """이미 붙은 개인운동을 갈아 끼울 때도 실린 제안을 닫는다."""
    token = _tok(client)
    session_id = _pt(client, token, clean, 89, [_walk()])
    sid = _pending(db_session)

    r = client.put(
        f"/v1/trainer/schedule/{session_id}/routines",
        json={
            "personal_routines": [_walk("계단 오르기")],
            "suggestion_ids": [sid],
        },
        headers=_h(token),
    )

    assert r.status_code == 200, r.text
    assert _status(db_session, sid) == trainer_service.ROUTINE_CONSUMED


def test_attach_without_suggestion_ids_leaves_suggestions_alone(
    client, db_session, clean
):
    """옛 앱은 이 필드를 모른다 — 빠지면 아무 제안도 닫지 않는다."""
    token = _tok(client)
    session_id = _pt(client, token, clean, 90, [])
    sid = _pending(db_session)

    r = client.put(
        f"/v1/trainer/schedule/{session_id}/routines",
        json={"personal_routines": [_walk()]},
        headers=_h(token),
    )

    assert r.status_code == 200, r.text
    assert _status(db_session, sid) == trainer_service.ROUTINE_PENDING


def test_failed_attach_keeps_the_suggestion_pending(client, db_session, clean):
    """없는 일정이면 404 — 제안도 그대로 대기다."""
    token = _tok(client)
    sid = _pending(db_session)

    r = client.put(
        "/v1/trainer/schedule/no-such-session/routines",
        json={"personal_routines": [_walk()], "suggestion_ids": [sid]},
        headers=_h(token),
    )

    assert r.status_code == 404, r.text
    assert _status(db_session, sid) == trainer_service.ROUTINE_PENDING


def test_attach_ignores_other_members_suggestion(client, db_session, clean):
    """일정의 회원이 아닌 회원의 제안 id 는 닫지 않는다."""
    token = _tok(client)
    session_id = _pt(client, token, clean, 91, [])
    mine = _pending(db_session)
    theirs = _pending(db_session, OTHER_MEMBER)

    r = client.put(
        f"/v1/trainer/schedule/{session_id}/routines",
        json={"personal_routines": [_walk()], "suggestion_ids": [mine, theirs]},
        headers=_h(token),
    )

    assert r.status_code == 200, r.text
    assert _status(db_session, mine) == trainer_service.ROUTINE_CONSUMED
    assert _status(db_session, theirs) == trainer_service.ROUTINE_PENDING
