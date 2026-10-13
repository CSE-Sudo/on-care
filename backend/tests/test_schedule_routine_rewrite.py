"""PT 에 붙은 개인운동 고치기·회원 변경·완료 메모 (#3232). DB 필요.

일정 상세에서 붙은 개인운동을 고치거나, PT 의 회원을 바꾸거나, 미리 메모를 적어 둔
PT 를 완료할 때 데이터가 틀어지지 않는지 본다.
"""
from __future__ import annotations

from datetime import timedelta

from sqlalchemy import or_, select

from app.core import clock
from app.models.models import (
    ExerciseSession,
    RoutineHistory,
    TrainerRoutine,
    TrainerSchedule,
)
from app.services import exercise_service

MEMBER = "user-jisu"
OTHER_MEMBER = "user-taekyung"
_NAME_PREFIX = "일정 개인운동 고치기 테스트"

#: 이 파일이 만든 일정 id — 끝나고 이것만 지운다. 날짜로 지우면 시드 일정까지
#: 사라져 타임라인 개수를 세는 다른 테스트가 깨진다.
_MADE: list[str] = []


def _tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _cleanup(db_session) -> None:
    for routine in db_session.scalars(
        select(TrainerRoutine).where(
            TrainerRoutine.member_id.in_((MEMBER, OTHER_MEMBER)),
            or_(
                TrainerRoutine.name.like(f"{_NAME_PREFIX}%"),
                TrainerRoutine.schedule_id.in_(list(_MADE)),
            ),
        )
    ).all():
        db_session.delete(routine)
    db_session.flush()
    while _MADE:
        session_id = _MADE.pop()
        hist = db_session.get(RoutineHistory, f"sched-hist-{session_id}")
        if hist is not None:
            db_session.delete(hist)
        derived = db_session.get(
            ExerciseSession, f"{exercise_service.PT_EXERCISE_ID_PREFIX}{session_id}"
        )
        if derived is not None:
            db_session.delete(derived)
        row = db_session.get(TrainerSchedule, session_id)
        if row is not None:
            db_session.delete(row)
    db_session.commit()


def _program_only(client, token, day: str, time: str, **overrides) -> str:
    """개인운동 없이 프로그램만 실린 PT 를 만들고 일정 id 를 준다."""
    body: dict = {
        "date": day,
        "time": time,
        "client_name": "이지수",
        "member_id": MEMBER,
        "type": "1:1 PT",
        "duration_minutes": 30,
        "program": [{"name": "스쿼트", "sets": 3, "reps": 10}],
    }
    body.update(overrides)
    r = client.post("/v1/trainer/schedule", json=body, headers=_h(token))
    assert r.status_code == 201, r.text
    session_id: str = r.json()["id"]
    _MADE.append(session_id)
    return session_id


def _item(name: str, **overrides) -> dict:
    item: dict = {
        "name": f"{_NAME_PREFIX} {name}",
        "minutes": 20,
        "type": "유산소",
        "source": "ai",
    }
    item.update(overrides)
    return item


def _put_routines(client, token, session_id: str, items: list[dict]):
    return client.put(
        f"/v1/trainer/schedule/{session_id}/routines",
        json={"personal_routines": items},
        headers=_h(token),
    )


def _personal(db_session, session_id: str) -> list[TrainerRoutine]:
    db_session.expire_all()
    return list(
        db_session.scalars(
            select(TrainerRoutine)
            .where(
                TrainerRoutine.schedule_id == session_id,
                TrainerRoutine.delivery_kind.is_not(None),
            )
            .order_by(TrainerRoutine.sort_order, TrainerRoutine.id)
        ).all()
    )


def test_adding_routines_to_two_pts_attached_without_a_key(client, db_session):
    """키 없이 처음 붙인 두 PT 에 운동을 하나씩 더해도 500 이 나지 않는다.

    예전에는 새 줄 키가 `None#routine1` 로 같아져 유니크 제약에 걸렸다.
    """
    token = _tok(client)
    day = (clock.today() + timedelta(days=90)).isoformat()
    try:
        first = _program_only(client, token, day, "20:00")
        second = _program_only(client, token, day, "21:00")
        for session_id in (first, second):
            r = _put_routines(client, token, session_id, [_item("걷기")])
            assert r.status_code == 200, r.text
        for session_id in (first, second):
            r = _put_routines(
                client, token, session_id, [_item("걷기"), _item("자전거")]
            )
            assert r.status_code == 200, r.text
            assert [x["name"] for x in r.json()] == [
                f"{_NAME_PREFIX} 걷기",
                f"{_NAME_PREFIX} 자전거",
            ]
        for session_id in (first, second):
            rows = _personal(db_session, session_id)
            assert [row.client_request_id for row in rows] == [None, None]
            # 새 줄도 그 PT 날짜를 들고 있다.
            assert {row.exercise_date for row in rows} == {day}
    finally:
        _cleanup(db_session)


def test_rewriting_keeps_intensity_reason_and_type_rules(client, db_session):
    """고칠 때도 강도·사유가 남고, 근력이 아니면 세트·횟수·중량을 비운다."""
    token = _tok(client)
    day = (clock.today() + timedelta(days=91)).isoformat()
    try:
        session_id = _program_only(client, token, day, "20:00")
        r = _put_routines(
            client,
            token,
            session_id,
            [_item("스쿼트", type="근력", minutes=10, sets=3, reps=12, weight=20)],
        )
        assert r.status_code == 200, r.text

        # 강도만 바꿔도 손댄 것이다 — AI 출처를 트레이너 것으로 넘긴다.
        r = _put_routines(
            client,
            token,
            session_id,
            [
                _item(
                    "스쿼트",
                    type="근력",
                    minutes=10,
                    sets=3,
                    reps=12,
                    weight=20,
                    intensity="high",
                    reason="하체 보강",
                )
            ],
        )
        assert r.status_code == 200, r.text
        [row] = _personal(db_session, session_id)
        assert (row.intensity, row.reason, row.source) == ("high", "하체 보강", "trainer")

        # 유산소로 바꾸면 옛 세트·횟수·중량을 들고 가지 않는다.
        r = _put_routines(
            client,
            token,
            session_id,
            [
                _item(
                    "스쿼트",
                    type="유산소",
                    minutes=15,
                    sets=3,
                    reps=12,
                    weight=20,
                    intensity="light",
                )
            ],
        )
        assert r.status_code == 200, r.text
        [row] = _personal(db_session, session_id)
        assert (row.type, row.sets, row.reps, row.weight) == ("유산소", None, None, None)
        assert row.intensity == "light"

        # 버티는 운동은 횟수를 비운다.
        r = _put_routines(
            client,
            token,
            session_id,
            [_item("플랭크", type="근력", minutes=0, sets=3, reps=10, hold_seconds=45)],
        )
        assert r.status_code == 200, r.text
        [row] = _personal(db_session, session_id)
        assert (row.sets, row.reps, row.hold_seconds) == (3, None, 45)
    finally:
        _cleanup(db_session)


def test_changing_the_member_clears_the_previous_members_rows(client, db_session):
    """회원을 바꾸면 이전 회원의 미전송 줄이 남지 않고, 완료 전송은 새 회원에게만 간다."""
    token = _tok(client)
    day = (clock.today() - timedelta(days=1)).isoformat()
    before = set(
        db_session.scalars(
            select(TrainerRoutine.id).where(TrainerRoutine.member_id == OTHER_MEMBER)
        ).all()
    )
    try:
        session_id = _program_only(client, token, day, "22:30")
        r = _put_routines(client, token, session_id, [_item("걷기")])
        assert r.status_code == 200, r.text
        assert _personal(db_session, session_id)

        r = client.put(
            f"/v1/trainer/schedule/{session_id}",
            json={"member_id": OTHER_MEMBER, "client_name": "류태경"},
            headers=_h(token),
        )
        assert r.status_code == 200, r.text
        db_session.expire_all()
        left = db_session.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.schedule_id == session_id,
                TrainerRoutine.status == "scheduled",
            )
        ).all()
        assert left == []

        assert client.post(
            f"/v1/trainer/schedule/{session_id}/complete",
            json={"note": ""},
            headers=_h(token),
        ).status_code == 200
        sent = client.post(
            f"/v1/trainer/schedule/{session_id}/program/send",
            json={},
            headers=_h(token),
        )
        assert sent.status_code == 200, sent.text
        db_session.expire_all()
        owners = set(
            db_session.scalars(
                select(TrainerRoutine.member_id).where(
                    TrainerRoutine.schedule_id == session_id,
                )
            ).all()
        )
        assert MEMBER not in owners
    finally:
        # 전송이 새 회원에게 배정한 줄도 지운다.
        db_session.expire_all()
        for routine in db_session.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.member_id == OTHER_MEMBER,
                TrainerRoutine.id.not_in(list(before) or [""]),
            )
        ).all():
            db_session.delete(routine)
        db_session.commit()
        _cleanup(db_session)


def test_completing_keeps_the_note_written_in_advance(client, db_session):
    """완료 요청에 메모가 없으면 미리 적어 둔 일정 메모가 이력에 남는다."""
    token = _tok(client)
    day = (clock.today() - timedelta(days=1)).isoformat()
    try:
        session_id = _program_only(
            client, token, day, "23:00", note="스쿼트 무릎 각도 확인"
        )
        r = client.post(
            f"/v1/trainer/schedule/{session_id}/complete",
            json={"note": ""},
            headers=_h(token),
        )
        assert r.status_code == 200, r.text
        db_session.expire_all()
        hist = db_session.get(RoutineHistory, f"sched-hist-{session_id}")
        assert hist is not None
        assert hist.trainer_note == "스쿼트 무릎 각도 확인"
    finally:
        _cleanup(db_session)
