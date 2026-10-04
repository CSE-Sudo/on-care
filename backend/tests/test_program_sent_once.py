"""PT 프로그램은 전송 때 한 번만 회원에게 간다 (#2279). DB 필요.

프로그램 만들기로 짠 PT 는 등록 때 회원에게 배정되고, PT 를 마치고 전송할 때
또 한 벌이 배정됐다 — 회원은 같은 운동을 두 번 해야 하는 것으로 봤다. 이제
등록은 일정에 붙여만 두고, 회원에게 가는 것은 전송 한 번뿐이다.
"""
from __future__ import annotations

from sqlalchemy import select

from app.core import clock
from app.models.models import TrainerRoutine, TrainerSchedule

MEMBER = "user-jisu"
TRAINER = "trainer-demo"
_SCHEDULE_URL = f"/v1/trainer/clients/{MEMBER}/program-schedule"
_NAME = "두벌 테스트"
#: 이 파일이 만든 일정 id — 끝나고 이것만 지운다(시드를 지우면 다른 테스트가 깨진다).
_MADE: list[str] = []


def _tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _member_token(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "jisu@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _member_routines(client, token: str) -> list[str]:
    res = client.get("/v1/me/coach/routines", headers=_h(token)).json()
    rows = res if isinstance(res, list) else res.get("routines", [])
    return [r.get("name") or "" for r in rows]


def _cleanup(db_session) -> None:
    while _MADE:
        row = db_session.get(TrainerSchedule, _MADE.pop())
        if row is not None:
            db_session.delete(row)
    for rt in db_session.scalars(
        select(TrainerRoutine).where(TrainerRoutine.member_id == MEMBER)
    ).all():
        if _NAME in (rt.name or "") or _NAME in (rt.program_name or ""):
            db_session.delete(rt)
    db_session.commit()


def _attach(client, token, *, time: str = "13:40") -> str:
    day = clock.today().isoformat()
    r = client.post(
        _SCHEDULE_URL,
        json={
            "name": _NAME,
            "sessions": [
                {
                    "id": "s1",
                    "name": "A",
                    "exercises": [
                        {
                            "id": "e1",
                            "name": f"{_NAME} 스쿼트",
                            "type": "근력",
                            "sets": 3,
                            "reps": 10,
                        }
                    ],
                }
            ],
            "date": day,
            "time": time,
            "duration_minutes": 30,
            "client_name": "이지수",
            "personal_routines": [
                {
                    "name": f"{_NAME} 걷기",
                    "minutes": 30,
                    "type": "유산소",
                    "source": "ai",
                }
            ],
        },
        headers=_h(token),
    )
    assert r.status_code == 201, r.text
    session_id: str = r.json()["session"]["id"]
    assert not session_id.startswith("seed-"), "시드 일정에 붙었다"
    _MADE.append(session_id)
    return session_id


def _program_rows(db_session, session_id: str) -> list[TrainerRoutine]:
    """그 PT 에 붙은 **프로그램** 줄. 개인운동은 `delivery_kind` 를 달고 있다."""
    return list(
        db_session.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.schedule_id == session_id,
                TrainerRoutine.delivery_kind.is_(None),
            )
        ).all()
    )


def _program_lines(db_session) -> list[TrainerRoutine]:
    """이 회원이 받은 PT 프로그램 줄(개인운동 전송 종류가 없는 승인된 줄)."""
    return list(
        db_session.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.member_id == MEMBER,
                TrainerRoutine.delivery_kind.is_(None),
                TrainerRoutine.status == "approved",
            )
        ).all()
    )


def test_registering_does_not_reach_the_member(client, db_session):
    """등록만으로는 회원에게 가지 않는다 — 일정에 붙여만 둔다."""
    token = _tok(client)
    mtok = _member_token(client)
    _cleanup(db_session)
    try:
        before = _member_routines(client, mtok)
        session_id = _attach(client, token)

        db_session.expire_all()
        rows = _program_rows(db_session, session_id)
        assert rows, "프로그램이 그 PT 에 붙어 있어야 한다"
        assert [r.status for r in rows] == ["scheduled"]

        assert _member_routines(client, mtok) == before
    finally:
        _cleanup(db_session)


def test_the_program_reaches_the_member_once(client, db_session):
    """전송하면 한 벌만 간다 — 예전에는 등록 때와 전송 때 두 벌이 생겼다."""
    token = _tok(client)
    mtok = _member_token(client)
    _cleanup(db_session)
    try:
        before = _member_routines(client, mtok)
        session_id = _attach(client, token)
        assert client.post(
            f"/v1/trainer/schedule/{session_id}/complete",
            json={"note": ""},
            headers=_h(token),
        ).status_code == 200
        assert client.post(
            f"/v1/trainer/schedule/{session_id}/program/send",
            json={},
            headers=_h(token),
        ).status_code == 200

        added = [n for n in _member_routines(client, mtok) if n not in before]
        # 매일 하는 목록에는 개인운동만 걸린다 — PT 프로그램은 그날 PT 에서
        # 한 것이라 PT 기록으로 남는다(#3115).
        assert added == [f"{_NAME} 걷기"], added

        db_session.expire_all()
        rows = _program_rows(db_session, session_id)
        # 프로그램은 한 벌만 보냈다.
        assert [r.status for r in rows] == ["approved"]
        # 며칠 전에 짜 두었어도 회원에게는 오늘 받은 운동이다.
        today = clock.today().isoformat()
        assert rows[0].active_from == today
        # 하루도 목록에 걸리지 않는다(`ended_on == active_from`).
        assert rows[0].ended_on == today
    finally:
        _cleanup(db_session)


def test_a_program_without_attached_rows_still_sends(client, db_session):
    """붙은 줄이 없으면 예전처럼 새로 배정한다.

    스케줄에서 연필로 바로 짠 프로그램에는 붙은 줄이 없고, 이 칸이 생기기 전에
    만든 일정도 그렇다 — 그 길이 막히면 안 된다.
    """
    token = _tok(client)
    mtok = _member_token(client)
    _cleanup(db_session)
    try:
        before = _member_routines(client, mtok)
        program_before = {r.id for r in _program_lines(db_session)}
        session_id = _attach(client, token)
        # 붙은 프로그램 줄을 지워 `연필로 짠 프로그램` 과 같은 모양으로 만든다.
        db_session.expire_all()
        for row in _program_rows(db_session, session_id):
            db_session.delete(row)
        db_session.commit()

        client.post(
            f"/v1/trainer/schedule/{session_id}/complete",
            json={"note": ""},
            headers=_h(token),
        )
        assert client.post(
            f"/v1/trainer/schedule/{session_id}/program/send",
            json={},
            headers=_h(token),
        ).status_code == 200

        added = [n for n in _member_routines(client, mtok) if n not in before]
        # 새로 배정한 프로그램도 매일 목록에는 걸지 않는다(#3115).
        assert added == [f"{_NAME} 걷기"], added
        db_session.expire_all()
        sent = [
            r for r in _program_lines(db_session) if r.id not in program_before
        ]
        assert sent, "프로그램은 보낸 기록으로 남는다"
        assert all(r.ended_on == r.active_from for r in sent)
        for row in sent:
            db_session.delete(row)
        db_session.commit()
    finally:
        _cleanup(db_session)
