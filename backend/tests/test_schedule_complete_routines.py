"""PT 프로그램 전송·취소 때의 개인운동 (#2224). DB 필요.

개인운동은 PT 에 붙여 두었다가(#2223) **프로그램을 보낼 때 함께** 회원에게
간다 — 회원은 "오늘 한 것" 과 "혼자 할 것" 을 한 번에 받는다. 붙은 것이 없으면
전송을 막는다: 프로그램 만들기가 개인운동을 필수로 받으므로, 비어 있다는 것은
그 길을 지나지 않았다는 뜻이다.

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


#: 이 파일이 만든 일정 id — 끝나고 이것만 지운다.
#:
#: 날짜로 지우면 그날의 **시드 일정까지** 함께 사라져, 그 날짜의 타임라인
#: 개수를 세는 다른 테스트(`test_schedule_seeded_timeline`)가 함께 깨진다.
_MADE: list[str] = []


def _cleanup(db_session, day: str) -> None:
    del day  # 날짜가 아니라 만든 id 로 지운다.
    while _MADE:
        row = db_session.get(TrainerSchedule, _MADE.pop())
        if row is not None:
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
        # 시드 일정(10·12·14·16·17·18·19시)과 겹치지 않는 시각이다. 겹치면
        # 프로그램이 **그 시드 일정에 붙고** id 가 시드 것이 되어, 뒷정리가
        # 그날의 시드를 지워 버린다 — 타임라인 개수를 세는 다른 테스트가
        # 함께 깨진다.
        "time": "13:00",
        "duration_minutes": 30,
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
    session_id: str = r.json()["session"]["id"]
    assert not session_id.startswith("seed-"), (
        "시드 일정에 붙었다 — 뒷정리가 남의 것을 지운다"
    )
    _MADE.append(session_id)
    return session_id


def _routines(db_session, session_id: str) -> list[TrainerRoutine]:
    return list(
        db_session.scalars(
            select(TrainerRoutine)
            .where(TrainerRoutine.schedule_id == session_id)
            .order_by(TrainerRoutine.sort_order)
        ).all()
    )


def _complete(client, token, session_id: str) -> None:
    assert client.post(
        f"/v1/trainer/schedule/{session_id}/complete",
        json={"note": ""},
        headers=_h(token),
    ).status_code == 200


def test_sending_the_program_sends_its_personal_routines(client, db_session):
    """프로그램을 보내면 개인운동도 함께 간다 — 오늘부터 7일. (#2224)"""
    token = _tok(client)
    day = clock.today().isoformat()
    _cleanup(db_session, day)
    try:
        session_id = _attach(client, token, day)
        _complete(client, token, session_id)

        db_session.expire_all()
        # 완료만으로는 가지 않는다 — 보내는 자리는 프로그램 전송이다.
        assert [r.status for r in _routines(db_session, session_id)] == [
            "scheduled"
        ]
        assert client.post(
            f"/v1/trainer/schedule/{session_id}/program/send",
            json={},
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


def test_sent_routines_stay_on_the_session(client, db_session):
    """보낸 뒤에도 그 PT 의 개인운동 목록에 남는다 — `pending_send` 만 내린다.

    트레이너가 나중에 그 PT 를 열어 "이 회원에게 무엇을 딸려 보냈나" 를 볼 데가
    일정 상세뿐이다. 보내자마자 목록에서 빼면 보낸 기록을 어디서도 확인할 수
    없다. (#2224)
    """
    token = _tok(client)
    day = clock.today().isoformat()
    _cleanup(db_session, day)
    try:
        session_id = _attach(client, token, day)
        _complete(client, token, session_id)
        url = f"/v1/trainer/schedule/{session_id}/routines"

        before = client.get(url, headers=_h(token)).json()
        assert [r["pending_send"] for r in before] == [True]

        assert client.post(
            f"/v1/trainer/schedule/{session_id}/program/send",
            json={},
            headers=_h(token),
        ).status_code == 200

        after = client.get(url, headers=_h(token)).json()
        assert [r["name"] for r in after] == [r["name"] for r in before]
        assert [r["pending_send"] for r in after] == [False]
    finally:
        _cleanup(db_session, day)


def test_sending_without_personal_routines_still_works(client, db_session):
    """붙은 개인운동이 없어도 프로그램은 보낼 수 있다. (#2224)

    개인운동을 필수로 받는 자리는 프로그램 만들기다(#2223). 스케줄에서 연필로
    바로 짠 프로그램에는 붙을 자리가 없어, 여기서 막으면 그 길로 짠 프로그램을
    보낼 수 없게 된다.
    """
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
                "program": [{"name": "스쿼트", "sets": 3, "reps": 10}],
            },
            headers=_h(token),
        )
        assert r.status_code == 201, r.text
        session_id = r.json()["id"]
        _MADE.append(session_id)

        _complete(client, token, session_id)
        sent = client.post(
            f"/v1/trainer/schedule/{session_id}/program/send",
            json={},
            headers=_h(token),
        )
        assert sent.status_code == 200, sent.text
    finally:
        _cleanup(db_session, day)


def test_a_new_send_retires_the_previous_personal_routines(client, db_session):
    """새로 보내면 이전 개인운동을 내린다 — 회원이 두 배를 받지 않는다. (#2224)"""
    token = _tok(client)
    day = clock.today().isoformat()
    _cleanup(db_session, day)
    try:
        first = _attach(client, token, day)
        _complete(client, token, first)
        client.post(
            f"/v1/trainer/schedule/{first}/program/send", json={}, headers=_h(token)
        )
        second = _attach(client, token, day, time="18:00")
        _complete(client, token, second)
        client.post(
            f"/v1/trainer/schedule/{second}/program/send", json={}, headers=_h(token)
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


def test_reattaching_a_program_replaces_its_personal_routines(
    client, db_session
):
    """같은 PT 에 프로그램을 다시 붙이면 개인운동도 새것으로 갈린다. (#2224)

    `program_json` 은 덮어쓰면서 개인운동만 뒤에 쌓이면, 두 번 짠 트레이너가
    두 배를 보내게 된다 — 트레이너는 바꾼 것으로 아는데 회원은 더해진 것을
    받는다.
    """
    token = _tok(client)
    day = clock.today().isoformat()
    _cleanup(db_session, day)
    try:
        first = _attach(client, token, day)
        second = _attach(
            client,
            token,
            day,
            name=f"{_NAME_PREFIX} PT 다시",
            personal_routines=[
                {
                    "name": f"{_NAME_PREFIX} 실내 자전거",
                    "minutes": 20,
                    "type": "유산소",
                    "source": "trainer",
                }
            ],
        )
        # 같은 시간대라 그 PT 에 다시 붙는다 — 새 일정이 생기지 않는다.
        assert second == first

        db_session.expire_all()
        rows = _routines(db_session, first)
        assert [r.name for r in rows] == [f"{_NAME_PREFIX} 실내 자전거"]
    finally:
        _cleanup(db_session, day)


def test_editing_an_ai_routine_makes_it_the_trainers(client, db_session):
    """AI 가 제안한 개인운동도 트레이너가 고치면 트레이너 것이 된다. (#2223, #2224)

    그대로 두면 트레이너가 손본 운동을 회원이 `AI 추천` 으로 본다. 프로그램
    만들기가 이미 같은 규칙으로 움직인다 — 상세 일정에서 고치는 길도 같아야
    한다. 손대지 않은 줄은 출처가 그대로다.
    """
    token = _tok(client)
    day = clock.today().isoformat()
    _cleanup(db_session, day)
    try:
        session_id = _attach(
            client,
            token,
            day,
            personal_routines=[
                {
                    "name": f"{_NAME_PREFIX} 걷기",
                    "minutes": 30,
                    "type": "유산소",
                    "source": "ai",
                },
                {
                    "name": f"{_NAME_PREFIX} 스트레칭",
                    "minutes": 10,
                    "type": "스트레칭",
                    "source": "ai",
                },
            ],
        )
        # 첫 줄만 시간을 줄인다. 두 번째 줄은 그대로 되돌려 보낸다.
        r = client.put(
            f"/v1/trainer/schedule/{session_id}/routines",
            json={
                "personal_routines": [
                    {
                        "name": f"{_NAME_PREFIX} 걷기",
                        "minutes": 15,
                        "type": "유산소",
                        "source": "ai",
                    },
                    {
                        "name": f"{_NAME_PREFIX} 스트레칭",
                        "minutes": 10,
                        "type": "스트레칭",
                        "source": "ai",
                    },
                ]
            },
            headers=_h(token),
        )
        assert r.status_code == 200, r.text

        db_session.expire_all()
        rows = _routines(db_session, session_id)
        assert [row.minutes for row in rows] == [15, 10]
        # 손댄 줄만 트레이너 것이 된다 — 클라이언트가 `ai` 로 보내도 그렇다.
        assert [row.source for row in rows] == ["trainer", "ai"]
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
