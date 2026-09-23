"""PT 일정에 붙는 개인운동과 `개인운동만` 전송 (#2223). DB 필요.

프로그램 만들기에서 PT 프로그램과 함께 정한 개인운동은 그 PT 일정에 붙어 있다가
PT 완료 때 회원에게 간다(#2224). 붙여 두는 동안은 회원에게 보이지 않아야 하고,
트레이너의 배정 목록에도 섞이면 안 된다.

PT 없이 `개인운동만` 보낸 전송은 붙일 일정이 없으므로 바로 배정되고, 이력이
종류를 구분할 수 있게 `delivery_kind` 와 한마디가 남는다(#2225).
"""
from __future__ import annotations

from datetime import timedelta

from sqlalchemy import or_, select

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
            or_(
                TrainerRoutine.name.like(f"{_NAME_PREFIX}%"),
                TrainerRoutine.program_name.like(f"{_NAME_PREFIX}%"),
            ),
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


def _routine_only_body(request_id: str) -> dict:
    """`개인운동만` 전송 본문 — 운동 하나가 세션 하나다. (#2223)

    트레이너 웹이 이렇게 보낸다: 운동 하나가 배정 한 건이 되어야 회원이 운동
    하나씩 완료를 표시할 수 있다.
    """
    return {
        "name": f"{_NAME_PREFIX} 이번 주 개인운동",
        "sessions": [
            {
                "id": "session-walk",
                "name": "걷기",
                "exercises": [{"id": "ex-1", "name": "걷기", "duration": 30}],
            },
            {
                "id": "session-plank",
                "name": "플랭크",
                "exercises": [
                    {
                        "id": "ex-2",
                        "name": "플랭크",
                        "type": "근력",
                        "sets": 3,
                        "hold_seconds": 45,
                    }
                ],
            },
        ],
        "delivery_kind": "routine_only",
        "active_days": 7,
        "client_request_id": request_id,
    }


def test_routine_only_delivery_stays_on_the_list_for_a_week(client, db_session):
    """`개인운동만` 은 보낸 날부터 한 주 동안 회원 목록에 걸린다. (#2223)

    추천 개인운동은 매일 새로 체크하는 목록이고 그 기간은
    `active_from`~`ended_on` 이 정한다(#2161) — 날마다 행을 만들지 않는다.
    시작일은 트레이너가 고르지 않는다: 보낸 날이 곧 시작일이다.
    """
    token = _tok(client)
    _cleanup_routines(db_session)
    try:
        r = client.post(
            _PROGRAM_URL,
            json=_routine_only_body("req-2223-only"),
            headers=_h(token),
        )
        assert r.status_code == 201, r.text
        rows = r.json()

        # 운동 하나가 배정 한 건이다 — 회원이 하나씩 완료를 표시할 수 있다.
        assert [row["session_name"] for row in rows] == ["걷기", "플랭크"]
        assert {row["delivery_kind"] for row in rows} == {"routine_only"}
        # 붙일 PT 일정이 없다.
        assert {row["schedule_id"] for row in rows} == {None}

        today = clock.today()
        db_session.expire_all()
        saved = db_session.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.member_id == MEMBER,
                TrainerRoutine.program_name
                == f"{_NAME_PREFIX} 이번 주 개인운동",
            )
        ).all()
        assert {row.active_from for row in saved} == {today.isoformat()}
        # 이레째 다음 날부터 목록에서 내려간다(`ended_on` 은 그날부터 없음).
        assert {row.ended_on for row in saved} == {
            (today + timedelta(days=7)).isoformat()
        }

        # 바로 보낸 것이므로 회원이 보는 목록에 들어간다.
        assigned = client.get(
            f"/v1/trainer/clients/{MEMBER}/routines", headers=_h(token)
        )
        assert {row["id"] for row in rows} <= {
            row["id"] for row in assigned.json()
        }
    finally:
        _cleanup_routines(db_session)


def test_routine_only_retry_does_not_send_a_second_week(client, db_session):
    """응답을 잃고 같은 키로 다시 보내도 한 주가 두 벌 가지 않는다. (#2223)"""
    token = _tok(client)
    _cleanup_routines(db_session)
    body = _routine_only_body("req-2223-only-retry")
    try:
        first = client.post(_PROGRAM_URL, json=body, headers=_h(token))
        retry = client.post(_PROGRAM_URL, json=body, headers=_h(token))

        assert first.status_code == 201, first.text
        assert retry.status_code == 201, retry.text
        assert len(first.json()) == 2
        assert [row["id"] for row in retry.json()] == [
            row["id"] for row in first.json()
        ]
        db_session.expire_all()
        rows = db_session.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.member_id == MEMBER,
                TrainerRoutine.program_name
                == f"{_NAME_PREFIX} 이번 주 개인운동",
            )
        ).all()
        assert len(rows) == 2
    finally:
        _cleanup_routines(db_session)
