"""PT 일정에 붙는 개인운동과 `개인운동만` 전송 (#2223). DB 필요.

프로그램 만들기에서 PT 프로그램과 함께 정한 개인운동은 그 PT 일정에 붙어 있다가
PT 완료 때 회원에게 간다(#2224). 붙여 두는 동안은 회원에게 보이지 않아야 하고,
트레이너의 배정 목록에도 섞이면 안 된다.

PT 없이 `개인운동만` 보낸 전송은 붙일 일정이 없으므로 바로 배정되고, 이력이
종류를 구분할 수 있게 `delivery_kind` 와 한마디가 남는다(#2225).
"""
from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select

from app.core import clock
from app.models.models import TrainerRoutine, TrainerSchedule

MEMBER = "user-jisu"
TRAINER = "trainer-demo"
_PROGRAM_SCHEDULE_URL = f"/v1/trainer/clients/{MEMBER}/program-schedule"
_PROGRAM_URL = f"/v1/trainer/clients/{MEMBER}/program"
_NAME_PREFIX = "개인운동 단계 테스트"


def _tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _cleanup_routines(db_session) -> None:
    """이 파일이 만든 개인운동만 지운다. 일정은 건드리지 않는다 — 시드 일정을
    지우면 그 날짜의 타임라인을 세는 다른 테스트가 함께 깨진다."""
    for routine in db_session.scalars(
        select(TrainerRoutine).where(
            TrainerRoutine.member_id == MEMBER,
            TrainerRoutine.name.like(f"{_NAME_PREFIX}%"),
        )
    ).all():
        db_session.delete(routine)
    db_session.commit()


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
            TrainerRoutine.name.like(f"{_NAME_PREFIX}%"),
        )
    ).all():
        db_session.delete(routine)
    db_session.commit()


def _body(day: str, request_id: str | None = None, **overrides) -> dict:
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
        "client_request_id": request_id,
        "personal_routines": [
            {
                "name": f"{_NAME_PREFIX} 걷기",
                "minutes": 30,
                "type": "유산소",
                "reason": "PT 사이 유산소",
                "source": "ai",
            },
            {
                "name": f"{_NAME_PREFIX} 플랭크",
                "minutes": 0,
                "type": "근력",
                "sets": 3,
                "hold_seconds": 45,
                "source": "trainer",
            },
        ],
    }
    body.update(overrides)
    return body


def test_personal_routines_attach_to_the_pt_session(client, db_session):
    """개인운동이 그 PT 일정에 붙고, 보내기 전에는 회원에게 가지 않는다. (#2223)"""
    token = _tok(client)
    day = (clock.today() + timedelta(days=70)).isoformat()
    _cleanup(db_session, day)
    try:
        r = client.post(
            _PROGRAM_SCHEDULE_URL, json=_body(day), headers=_h(token)
        )
        assert r.status_code == 201, r.text
        data = r.json()
        session_id = data["session"]["id"]
        personal = data["personal_routines"]

        assert [p["name"] for p in personal] == [
            f"{_NAME_PREFIX} 걷기",
            f"{_NAME_PREFIX} 플랭크",
        ]
        # 붙은 일정·전송 종류·날짜가 함께 남는다.
        assert {p["schedule_id"] for p in personal} == {session_id}
        assert {p["delivery_kind"] for p in personal} == {"pt_with_routine"}
        assert {p["exercise_date"] for p in personal} == {day}
        # 버티는 운동은 초가 남고 횟수는 비운다(#1969).
        plank = personal[1]
        assert (plank["hold_seconds"], plank["reps"]) == (45, None)

        # 일정에 붙은 개인운동은 그 일정에서 조회할 수 있다.
        listed = client.get(
            f"/v1/trainer/schedule/{session_id}/routines", headers=_h(token)
        )
        assert listed.status_code == 200, listed.text
        assert [p["id"] for p in listed.json()] == [p["id"] for p in personal]

        # 아직 보낸 것이 아니므로 배정 목록(회원이 보는 것과 같은 조건)에는 없다.
        assigned = client.get(
            f"/v1/trainer/clients/{MEMBER}/routines", headers=_h(token)
        )
        assert assigned.status_code == 200, assigned.text
        names = {row["name"] for row in assigned.json()}
        assert f"{_NAME_PREFIX} 걷기" not in names
        # AI 제안 검토 목록에도 섞이지 않는다 — 검토할 후보가 아니다.
        suggestions = client.get(
            f"/v1/trainer/clients/{MEMBER}/routine-suggestions", headers=_h(token)
        )
        assert suggestions.status_code == 200, suggestions.text
        assert f"{_NAME_PREFIX} 걷기" not in {
            row["name"] for row in suggestions.json()
        }
    finally:
        _cleanup(db_session, day)


def test_personal_routines_are_idempotent_on_retry(client, db_session):
    """응답을 잃고 같은 키로 다시 보내도 개인운동이 두 벌 붙지 않는다. (#2223)"""
    token = _tok(client)
    day = (clock.today() + timedelta(days=71)).isoformat()
    _cleanup(db_session, day)
    body = _body(day, request_id="req-2223-retry")
    try:
        first = client.post(_PROGRAM_SCHEDULE_URL, json=body, headers=_h(token))
        retry = client.post(_PROGRAM_SCHEDULE_URL, json=body, headers=_h(token))

        assert first.status_code == 201, first.text
        assert retry.status_code == 201, retry.text
        assert retry.json()["personal_routines"] == first.json()["personal_routines"]
        db_session.expire_all()
        rows = db_session.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.member_id == MEMBER,
                TrainerRoutine.name.like(f"{_NAME_PREFIX} 걷기"),
            )
        ).all()
        assert len(rows) == 1
    finally:
        _cleanup(db_session, day)


def test_program_schedule_without_personal_routines_still_works(client, db_session):
    """개인운동 단계가 없던 옛 앱·저장 초안이 보내는 요청은 그대로 받는다."""
    token = _tok(client)
    day = (clock.today() + timedelta(days=72)).isoformat()
    _cleanup(db_session, day)
    try:
        body = _body(day)
        body.pop("personal_routines")
        r = client.post(_PROGRAM_SCHEDULE_URL, json=body, headers=_h(token))
        assert r.status_code == 201, r.text
        assert r.json()["personal_routines"] == []
    finally:
        _cleanup(db_session, day)


def test_routine_only_delivery_goes_straight_to_the_member(client, db_session):
    """`개인운동만` 은 붙일 일정이 없어 바로 배정되고, 종류와 한마디가 남는다. (#2223)"""
    token = _tok(client)
    day = clock.today().isoformat()
    _cleanup_routines(db_session)
    try:
        r = client.post(
            _PROGRAM_URL,
            json={
                "name": f"{_NAME_PREFIX} 이번 주 개인운동",
                "sessions": [
                    {
                        "id": "session-1",
                        "name": "세션 A",
                        "exercises": [
                            {"id": "ex-1", "name": "걷기", "duration": 30},
                        ],
                    }
                ],
                "delivery_kind": "routine_only",
                "trainer_message": "이번 주는 PT 쉬어요, 이것만 챙겨 주세요",
                "start_date": day,
                "client_request_id": "req-2223-only",
            },
            headers=_h(token),
        )
        assert r.status_code == 201, r.text
        [routine] = r.json()
        assert routine["delivery_kind"] == "routine_only"
        assert routine["trainer_message"] == "이번 주는 PT 쉬어요, 이것만 챙겨 주세요"
        assert routine["exercise_date"] == day
        # 붙일 PT 일정이 없다.
        assert routine["schedule_id"] is None

        # 바로 보낸 것이므로 회원이 보는 목록에 들어간다.
        assigned = client.get(
            f"/v1/trainer/clients/{MEMBER}/routines", headers=_h(token)
        )
        assert routine["id"] in {row["id"] for row in assigned.json()}
    finally:
        _cleanup_routines(db_session)
