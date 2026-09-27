"""전송 이력의 `직전 전송` 묶음과 미전송 개인운동 (#2225). DB 필요.

전송 이력이 PT 프로그램과 개인운동을 따로 나열하던 동안에는, PT 완료 때 함께
보낸 개인운동이 어느 PT 와 짝인지 알 수 없었다(#2224). 한 번의 전송이 만든 줄은
멱등키의 `#` 앞부분을 함께 쓰므로 그 값으로 묶는다.
"""
from __future__ import annotations

from sqlalchemy import select

from app.core import clock
from app.models.models import TrainerRoutine, TrainerSchedule

MEMBER = "user-jisu"
_SCHEDULE_URL = f"/v1/trainer/clients/{MEMBER}/program-schedule"
_LATEST_URL = f"/v1/trainer/clients/{MEMBER}/deliveries/latest"
_UNSENT_URL = f"/v1/trainer/clients/{MEMBER}/routines/unsent"
_NAME = "이력 묶음 테스트"
#: 이 파일이 만든 일정 id — 끝나고 이것만 지운다(시드를 지우면 다른 테스트가 깨진다).
_MADE: list[str] = []


def _tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


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


def _attach(
    client, token, *, time: str = "13:40", request_id: str | None = "req"
) -> str:
    """그날 PT 를 만들고 개인운동을 붙인 뒤 일정 id 를 준다."""
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
            "date": clock.today().isoformat(),
            "time": time,
            "duration_minutes": 30,
            "client_name": "이지수",
            # 화면은 전송 시도마다 멱등키를 실어 보낸다(#581) — 한 전송이 만든
            # 줄을 묶는 값이기도 하다(#2225).
            **({"client_request_id": f"{request_id}-{time}"} if request_id else {}),
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


def test_unsent_lists_what_is_waiting_on_a_pt(client, db_session):
    """붙여만 두고 아직 보내지 않은 개인운동이 목록에 선다."""
    token = _tok(client)
    _cleanup(db_session)
    try:
        assert client.get(_UNSENT_URL, headers=_h(token)).json() == []
        session_id = _attach(client, token)

        rows = client.get(_UNSENT_URL, headers=_h(token)).json()
        assert [r["name"] for r in rows] == [f"{_NAME} 걷기"]
        # 어느 PT 의 것인지 알아야 그 자리에서 보낼 수 있다.
        assert rows[0]["schedule_id"] == session_id
        assert rows[0]["pending_send"] is True
        # 아직 보낸 것이 없으므로 직전 전송도 없다.
        assert client.get(_LATEST_URL, headers=_h(token)).json() is None
    finally:
        _cleanup(db_session)


def test_latest_delivery_groups_the_pt_with_its_routines(client, db_session):
    """PT 와 함께 간 전송은 그 PT 와 개인운동이 한 묶음으로 온다."""
    token = _tok(client)
    _cleanup(db_session)
    try:
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

        got = client.get(_LATEST_URL, headers=_h(token)).json()
        assert got is not None
        assert got["kind"] == "pt_with_routine"
        assert got["sent_on"] == clock.today().isoformat()
        # 어느 PT 와 짝인지 — 그 일정과 그날 한 운동이 함께 온다.
        assert got["session"]["id"] == session_id
        assert [p["name"] for p in got["session"]["program"]] == [
            f"{_NAME} 스쿼트"
        ]
        assert [r["name"] for r in got["routines"]] == [f"{_NAME} 걷기"]
        # 보냈으니 미전송 목록에서는 빠진다.
        assert client.get(_UNSENT_URL, headers=_h(token)).json() == []
    finally:
        _cleanup(db_session)


def test_cancelled_pt_delivery_says_so(client, db_session):
    """취소 뒤 개인운동만 보낸 전송은 종류가 그렇게 온다."""
    token = _tok(client)
    _cleanup(db_session)
    try:
        session_id = _attach(client, token)
        client.post(
            f"/v1/trainer/schedule/{session_id}/cancel",
            json={"source": "member", "reason": "몸살"},
            headers=_h(token),
        )
        assert client.post(
            f"/v1/trainer/schedule/{session_id}/routines/send",
            json={},
            headers=_h(token),
        ).status_code == 200

        got = client.get(_LATEST_URL, headers=_h(token)).json()
        assert got["kind"] == "cancelled_routine_only"
        assert [r["name"] for r in got["routines"]] == [f"{_NAME} 걷기"]
    finally:
        _cleanup(db_session)


def test_other_deliveries_do_not_leak_into_the_group(client, db_session):
    """다른 전송의 줄이 묶음에 섞이지 않는다 — 가장 최근 것만 온다."""
    token = _tok(client)
    _cleanup(db_session)
    try:
        first = _attach(client, token, time="13:40")
        client.post(
            f"/v1/trainer/schedule/{first}/complete",
            json={"note": ""},
            headers=_h(token),
        )
        client.post(
            f"/v1/trainer/schedule/{first}/program/send",
            json={},
            headers=_h(token),
        )
        second = _attach(client, token, time="20:00")
        client.post(
            f"/v1/trainer/schedule/{second}/complete",
            json={"note": ""},
            headers=_h(token),
        )
        client.post(
            f"/v1/trainer/schedule/{second}/program/send",
            json={},
            headers=_h(token),
        )

        got = client.get(_LATEST_URL, headers=_h(token)).json()
        assert got["session"]["id"] == second
        # 같은 날 두 번 보냈어도 묶음은 한 전송 몫이다.
        assert len(got["routines"]) == 1
    finally:
        _cleanup(db_session)


def test_old_rows_without_a_key_group_by_their_pt(client, db_session):
    """멱등키가 없던 옛 배정도 붙은 PT 로 묶인다.

    키는 #581 뒤에 생겼다. 그 전에 만들어진 줄은 `client_request_id` 가 비어
    있어, 같은 날 두 번 보냈으면 한 덩어리로 뭉쳐 보였다.
    """
    token = _tok(client)
    _cleanup(db_session)
    try:
        first = _attach(client, token, time="13:40", request_id=None)
        second = _attach(client, token, time="20:00", request_id=None)
        for sid in (first, second):
            client.post(
                f"/v1/trainer/schedule/{sid}/complete",
                json={"note": ""},
                headers=_h(token),
            )
            client.post(
                f"/v1/trainer/schedule/{sid}/program/send",
                json={},
                headers=_h(token),
            )

        got = client.get(_LATEST_URL, headers=_h(token)).json()
        assert got["session"]["id"] == second
        assert len(got["routines"]) == 1
    finally:
        _cleanup(db_session)
