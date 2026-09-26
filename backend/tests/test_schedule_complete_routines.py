"""PT 완료·취소 때의 개인운동 전송 (#2224). DB 필요.

개인운동은 PT 에 붙여 두었다가(#2223) **완료할 때** 회원에게 간다. 완료는 그
유일한 순간이므로 붙은 것이 없으면 완료를 막는다 — 그대로 완료하면 그 PT 의
개인운동은 영영 가지 않는다.

취소·노쇼로 끝난 PT 의 개인운동은 자동으로 가지 않는다. 아파서 쉬는 회원에게
운동이 저절로 가면 안 되기 때문이고, 트레이너가 고쳐서 보내거나 보내지 않기로
정리한다.
"""
from __future__ import annotations

from datetime import timedelta

from sqlalchemy import or_, select

from app.core import clock
from app.models.models import TrainerRoutine, TrainerSchedule

MEMBER = "user-jisu"
TRAINER = "trainer-demo"
_SCHEDULE_URL = f"/v1/trainer/clients/{MEMBER}/program-schedule"
_NAME_PREFIX = "완료 전송 테스트"


def _tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _cleanup(db_session, day: str) -> None:
    for row in db_session.scalars(
        select(TrainerSchedule).where(
            TrainerSchedule.trainer_id == TRAINER,
            TrainerSchedule.member_id == MEMBER,
            TrainerSchedule.date == day,
        )
    ).all():
        db_session.delete(row)
    for routine in db_session.scalars(
        select(TrainerRoutine).where(
            TrainerRoutine.member_id == MEMBER,
            or_(
                TrainerRoutine.name.like(f"{_NAME_PREFIX}%"),
                TrainerRoutine.program_name.like(f"{_NAME_PREFIX}%"),
            ),
        )
    ).all():
        db_session.delete(routine)
    db_session.commit()


def _body(day: str, **overrides) -> dict:
    body: dict = {
        "name": f"{_NAME_PREFIX} PT",
        "sessions": [
            {
                "id": "session-1",
                "name": "세션 A",
                "exercises": [{"id": "ex-1", "name": "스쿼트", "sets": 3}],
            }
        ],
        "date": day,
        "time": "16:00",
        "duration_minutes": 60,
        "client_name": "이지수",
        "personal_routines": [
            {
                "name": f"{_NAME_PREFIX} 걷기",
                "minutes": 30,
                "type": "유산소",
                "source": "ai",
            },
        ],
    }
    body.update(overrides)
    return body


def _attach(client, token, day: str, **overrides) -> str:
    """그날 PT 를 만들고 개인운동을 붙인 뒤 일정 id 를 준다."""
    r = client.post(
        _SCHEDULE_URL, json=_body(day, **overrides), headers=_h(token)
    )
    assert r.status_code == 201, r.text
    return r.json()["session"]["id"]


def _routines(db_session, session_id: str) -> list[TrainerRoutine]:
    return list(
        db_session.scalars(
            select(TrainerRoutine)
            .where(TrainerRoutine.schedule_id == session_id)
            .order_by(TrainerRoutine.sort_order)
        ).all()
    )


def test_completing_the_pt_sends_its_personal_routines(client, db_session):
    """완료하면 붙어 있던 개인운동이 회원에게 간다 — 오늘부터 7일. (#2224)"""
    token = _tok(client)
    day = clock.today().isoformat()
    _cleanup(db_session, day)
    try:
        session_id = _attach(client, token, day)
        assert client.post(
            f"/v1/trainer/schedule/{session_id}/complete",
            json={"note": ""},
            headers=_h(token),
        ).status_code == 200

        db_session.expire_all()
        sent = _routines(db_session, session_id)
        assert [r.status for r in sent] == ["approved"]
        row = sent[0]
        # 며칠 전에 짜 두었어도 회원에게는 **오늘** 받은 운동이다.
        assert row.active_from == clock.today().isoformat()
        assert row.ended_on == (
            clock.today() + timedelta(days=7)
        ).isoformat()
        assert row.delivery_kind == "pt_with_routine"
    finally:
        _cleanup(db_session, day)


def test_completing_without_personal_routines_is_refused(client, db_session):
    """붙은 개인운동이 없으면 완료를 막는다 — 그대로 두면 영영 안 간다. (#2224)"""
    token = _tok(client)
    day = clock.today().isoformat()
    _cleanup(db_session, day)
    try:
        r = client.post(
            "/v1/trainer/schedule",
            json={
                "date": day,
                "time": "17:00",
                "client_name": "이지수",
                "member_id": MEMBER,
                "type": "1:1 PT",
                "duration_minutes": 60,
            },
            headers=_h(token),
        )
        assert r.status_code == 201, r.text
        session_id = r.json()["id"]

        refused = client.post(
            f"/v1/trainer/schedule/{session_id}/complete",
            json={"note": ""},
            headers=_h(token),
        )
        assert refused.status_code == 400
        assert "개인운동" in refused.json()["detail"]

        db_session.expire_all()
        still = db_session.get(TrainerSchedule, session_id)
        assert still is not None and still.status == "예정"
    finally:
        _cleanup(db_session, day)


def test_a_new_send_retires_the_previous_personal_routines(client, db_session):
    """새로 보내면 이전 개인운동을 내린다 — 회원이 두 배를 받지 않는다. (#2224)"""
    token = _tok(client)
    day = clock.today().isoformat()
    _cleanup(db_session, day)
    try:
        first = _attach(client, token, day)
        client.post(
            f"/v1/trainer/schedule/{first}/complete",
            json={"note": ""},
            headers=_h(token),
        )
        second = _attach(client, token, day, time="18:00")
        client.post(
            f"/v1/trainer/schedule/{second}/complete",
            json={"note": ""},
            headers=_h(token),
        )

        db_session.expire_all()
        today = clock.today().isoformat()
        old = _routines(db_session, first)[0]
        new = _routines(db_session, second)[0]
        # 먼저 보낸 것은 오늘부로 내려가고, 방금 보낸 것만 걸려 있다.
        assert old.ended_on == today
        assert new.ended_on > today
    finally:
        _cleanup(db_session, day)


def test_cancelled_pt_keeps_its_routines_until_the_trainer_sends(
    client, db_session
):
    """취소해도 개인운동은 저절로 가지 않고, 눌러야 간다. (#2224)"""
    token = _tok(client)
    day = clock.today().isoformat()
    _cleanup(db_session, day)
    try:
        session_id = _attach(client, token, day)
        assert client.post(
            f"/v1/trainer/schedule/{session_id}/cancel",
            json={"source": "member", "reason": "몸살"},
            headers=_h(token),
        ).status_code == 200

        db_session.expire_all()
        # 취소만으로는 아무것도 가지 않는다 — 아픈 회원에게 운동이 저절로
        # 가면 안 된다.
        assert [r.status for r in _routines(db_session, session_id)] == [
            "scheduled"
        ]

        sent = client.post(
            f"/v1/trainer/schedule/{session_id}/routines/send",
            json={},
            headers=_h(token),
        )
        assert sent.status_code == 200, sent.text
        db_session.expire_all()
        rows = _routines(db_session, session_id)
        assert [r.status for r in rows] == ["approved"]
        assert rows[0].delivery_kind == "cancelled_routine_only"
    finally:
        _cleanup(db_session, day)


def test_the_trainer_can_edit_the_routines_before_sending(client, db_session):
    """취소된 PT 의 개인운동은 고쳐서 보낼 수 있다. (#2224)

    PT 가 열리지 않았으므로 "그 PT 다음에 할 것" 으로 짠 구성이 그대로 맞지
    않는다. 취소된 PT 에는 프로그램 만들기로 다시 붙일 수 없어 여기가 유일한
    고치는 자리다.
    """
    token = _tok(client)
    day = clock.today().isoformat()
    _cleanup(db_session, day)
    try:
        session_id = _attach(client, token, day)
        client.post(
            f"/v1/trainer/schedule/{session_id}/cancel",
            json={"source": "member", "reason": "몸살"},
            headers=_h(token),
        )
        sent = client.post(
            f"/v1/trainer/schedule/{session_id}/routines/send",
            json={
                "personal_routines": [
                    {
                        "name": f"{_NAME_PREFIX} 가벼운 스트레칭",
                        "minutes": 10,
                        "type": "스트레칭",
                        "source": "trainer",
                    }
                ]
            },
            headers=_h(token),
        )
        assert sent.status_code == 200, sent.text
        assert [r["name"] for r in sent.json()] == [
            f"{_NAME_PREFIX} 가벼운 스트레칭"
        ]

        db_session.expire_all()
        rows = _routines(db_session, session_id)
        assert [r.name for r in rows] == [f"{_NAME_PREFIX} 가벼운 스트레칭"]
        assert rows[0].minutes == 10
    finally:
        _cleanup(db_session, day)


def test_dismissing_clears_the_unsent_mark(client, db_session):
    """`보내지 않음` 은 표시를 걷되 무엇을 짰는지는 남긴다. (#2224)"""
    token = _tok(client)
    day = clock.today().isoformat()
    _cleanup(db_session, day)
    try:
        session_id = _attach(client, token, day)
        client.post(
            f"/v1/trainer/schedule/{session_id}/cancel",
            json={"source": "trainer", "reason": "일정 조정"},
            headers=_h(token),
        )
        r = client.post(
            f"/v1/trainer/schedule/{session_id}/routines/dismiss",
            headers=_h(token),
        )
        assert r.status_code == 200 and r.json()["dismissed"] is True

        db_session.expire_all()
        assert [r.status for r in _routines(db_session, session_id)] == [
            "dismissed"
        ]
        # 미전송 목록에서도 빠진다.
        listed = client.get(
            f"/v1/trainer/schedule/{session_id}/routines", headers=_h(token)
        )
        assert listed.json() == []
    finally:
        _cleanup(db_session, day)


def test_moving_the_pt_moves_its_personal_routines(client, db_session):
    """PT 날짜를 옮기면 붙은 개인운동도 따라간다 — 묻지도 보내지도 않는다. (#2224)"""
    token = _tok(client)
    day = (clock.today() + timedelta(days=71)).isoformat()
    moved = (clock.today() + timedelta(days=75)).isoformat()
    _cleanup(db_session, day)
    _cleanup(db_session, moved)
    try:
        session_id = _attach(client, token, day)
        r = client.put(
            f"/v1/trainer/schedule/{session_id}",
            json={"date": moved},
            headers=_h(token),
        )
        assert r.status_code == 200, r.text

        db_session.expire_all()
        rows = _routines(db_session, session_id)
        assert [x.exercise_date for x in rows] == [moved]
        # 옮긴 것만으로는 회원에게 가지 않는다.
        assert [x.status for x in rows] == ["scheduled"]
    finally:
        _cleanup(db_session, day)
        _cleanup(db_session, moved)
