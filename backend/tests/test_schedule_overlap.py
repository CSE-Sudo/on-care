"""일정·예약·상담 승인 경로의 시간 겹침 검사. (#2284)

예전 판정은 날짜와 시작 시각이 **같을 때만** 겹침으로 봤고, 그마저 반복 생성에서만
썼다. 그래서 10:00(60분) 위에 10:30 이 조용히 들어갔고, 단건 생성·수정·회원 예약·
슬롯 열기·상담 승인은 아예 겹침을 보지 않았다.

여기서는 경로마다 트레이너를 새로 만들어 시드 타임라인·다른 테스트의 일정과 섞이지
않게 한다. 날짜는 시드가 닿지 않는 먼 미래를 쓴다.
"""
from __future__ import annotations

from datetime import datetime, timedelta
from uuid import uuid4

import pytest

from app.core.clock import SEOUL
from app.core.security import hash_password
from app.models.models import (
    ConsultationRequest,
    Notification,
    TrainerClient,
    TrainerProfile,
    TrainerReservation,
    TrainerReservationSlot,
    TrainerRoutine,
    TrainerSchedule,
    User,
)
from app.services.trainer import _common as trainer_common_service
from app.services.trainer import schedule as trainer_schedule_service
from app.services.trainer.schedule import (
    SCHEDULE_OVERLAP_CODE,
    ScheduleOverlap,
    conflicting_sessions,
    ensure_no_overlap,
)

EMAIL_PREFIX = "overlap-2284-"
PASSWORD = "overlap-pw-1234"
DAY = "2031-03-10"
NEXT_DAY = "2031-03-11"


# ---- 준비 ----


@pytest.fixture(autouse=True)
def _cleanup(db_session):
    yield
    db_session.rollback()
    user_ids = [
        row[0]
        for row in db_session.query(User.id)
        .filter(User.email.like(f"{EMAIL_PREFIX}%"))
        .all()
    ]
    if not user_ids:
        return
    db_session.query(TrainerReservation).filter(
        TrainerReservation.member_id.in_(user_ids)
    ).delete(synchronize_session=False)
    db_session.query(TrainerRoutine).filter(
        (TrainerRoutine.trainer_id.in_(user_ids))
        | (TrainerRoutine.member_id.in_(user_ids))
    ).delete(synchronize_session=False)
    db_session.query(TrainerSchedule).filter(
        (TrainerSchedule.trainer_id.in_(user_ids))
        | (TrainerSchedule.member_id.in_(user_ids))
    ).delete(synchronize_session=False)
    db_session.query(ConsultationRequest).filter(
        (ConsultationRequest.member_id.in_(user_ids))
        | (ConsultationRequest.trainer_id.in_(user_ids))
    ).delete(synchronize_session=False)
    db_session.query(TrainerReservationSlot).filter(
        TrainerReservationSlot.trainer_id.in_(user_ids)
    ).delete(synchronize_session=False)
    db_session.query(TrainerClient).filter(
        (TrainerClient.trainer_id.in_(user_ids))
        | (TrainerClient.member_id.in_(user_ids))
    ).delete(synchronize_session=False)
    db_session.query(Notification).filter(
        Notification.user_id.in_(user_ids)
    ).delete(synchronize_session=False)
    db_session.query(TrainerProfile).filter(
        TrainerProfile.trainer_id.in_(user_ids)
    ).delete(synchronize_session=False)
    db_session.query(User).filter(User.id.in_(user_ids)).delete(
        synchronize_session=False
    )
    db_session.commit()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _trainer(client, db_session) -> tuple[str, str]:
    """로그인 가능한 새 트레이너. (id, token)"""
    suffix = uuid4().hex[:10]
    email = f"{EMAIL_PREFIX}trainer-{suffix}@oncare.com"
    trainer = User(
        id=f"overlap-trainer-{suffix}",
        email=email,
        name="겹침 테스트 트레이너",
        hashed_password=hash_password(PASSWORD),
        role="trainer",
        is_active=True,
    )
    db_session.add(trainer)
    db_session.flush()
    db_session.add(TrainerProfile(trainer_id=trainer.id))
    db_session.commit()
    return trainer.id, _login(client, email)


def _member(client, db_session, trainer_id: str | None = None) -> tuple[str, str]:
    """회원 계정. [trainer_id] 를 주면 그 트레이너의 담당으로 묶는다."""
    email = f"{EMAIL_PREFIX}member-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": "겹침 회원"},
    )
    assert response.status_code == 201, response.text
    member_id = response.json()["id"]
    if trainer_id is not None:
        db_session.add(
            TrainerClient(
                id=f"tc-{uuid4().hex[:12]}",
                trainer_id=trainer_id,
                member_id=member_id,
                active=True,
            )
        )
        db_session.commit()
    return member_id, _login(client, email)


def _row(
    db_session,
    trainer_id: str,
    *,
    day: str = DAY,
    time: str,
    minutes: int = 60,
    status: str = trainer_common_service.SCHEDULE_UPCOMING,
) -> str:
    """API 를 거치지 않고 일정 한 줄을 심는다(취소·노쇼·공백 같은 상태용)."""
    schedule_id = f"sched-{uuid4().hex[:12]}"
    db_session.add(
        TrainerSchedule(
            id=schedule_id,
            trainer_id=trainer_id,
            member_id=None,
            date=day,
            time=time,
            client_name="기존 일정",
            type="1:1 PT",
            duration_minutes=minutes,
            status=status,
            note="",
            program_json="[]",
            sort_order=0,
        )
    )
    db_session.commit()
    return schedule_id


def _create(client, token: str, **over):
    body = {
        "date": DAY,
        "time": "10:00",
        "client_name": "겹침 회원",
        "type": "1:1 PT",
        "duration_minutes": 60,
    }
    body.update(over)
    return client.post("/v1/trainer/schedule", json=body, headers=_auth(token))


def _assert_overlap(response, *, conflict_ids: list[str] | None = None) -> dict:
    assert response.status_code == 409, response.text
    detail = response.json()["detail"]
    assert detail["code"] == SCHEDULE_OVERLAP_CODE
    assert detail["message"]
    if conflict_ids is not None:
        assert [c["id"] for c in detail["conflicts"]] == conflict_ids
    return detail


def _kst(day: str, time: str) -> datetime:
    return datetime.fromisoformat(f"{day}T{time}:00").replace(tzinfo=SEOUL)


# ---- 판정 규칙 (conflicting_sessions) ----


@pytest.mark.parametrize(
    ("time", "minutes", "overlaps"),
    [
        ("10:30", 30, True),  # 안쪽에서 시작 — 이슈가 짚은 경우
        ("09:30", 60, True),  # 앞에서 걸쳐 들어온다
        ("09:00", 180, True),  # 기존 일정을 통째로 덮는다
        ("10:59", 10, True),  # 끝나기 1분 전
        ("10:00", 60, True),  # 똑같은 자리(예전 판정도 잡던 경우)
        ("11:00", 60, False),  # 끝나는 시각에 시작 — 이어질 뿐이다
        ("09:00", 60, False),  # 시작 시각에 끝난다
        ("12:00", 30, False),  # 떨어져 있다
    ],
)
def test_interval_rule(client, db_session, time, minutes, overlaps):
    trainer_id, _ = _trainer(client, db_session)
    existing = _row(db_session, trainer_id, time="10:00", minutes=60)

    found = conflicting_sessions(
        db_session, trainer_id, [(DAY, time)], duration_minutes=minutes
    )

    assert [c.id for c in found] == ([existing] if overlaps else [])


def test_zero_minute_sessions_occupy_their_start_minute(client, db_session):
    """길이 0인 일정은 시작 1분으로 본다 — 아예 안 보이면 같은 시각에 두 건이 선다."""
    trainer_id, _ = _trainer(client, db_session)
    existing = _row(db_session, trainer_id, time="10:00", minutes=0)

    same = conflicting_sessions(db_session, trainer_id, [(DAY, "10:00")])
    after = conflicting_sessions(db_session, trainer_id, [(DAY, "10:01")])
    around = conflicting_sessions(
        db_session, trainer_id, [(DAY, "09:30")], duration_minutes=60
    )

    assert [c.id for c in same] == [existing]
    assert after == []
    assert [c.id for c in around] == [existing]


@pytest.mark.parametrize(
    ("status", "occupies"),
    [
        (trainer_common_service.SCHEDULE_UPCOMING, True),
        (trainer_common_service.SCHEDULE_DONE, True),
        (trainer_common_service.SCHEDULE_CANCELLED, False),
        (trainer_common_service.SCHEDULE_NO_SHOW, False),
        (trainer_common_service.SCHEDULE_GAP, False),
    ],
)
def test_only_occupying_statuses_block(client, db_session, status, occupies):
    trainer_id, _ = _trainer(client, db_session)
    existing = _row(db_session, trainer_id, time="10:00", status=status)

    found = conflicting_sessions(
        db_session, trainer_id, [(DAY, "10:30")], duration_minutes=30
    )

    assert [c.id for c in found] == ([existing] if occupies else [])


def test_other_trainers_sessions_do_not_block(client, db_session):
    trainer_id, _ = _trainer(client, db_session)
    other_id, _ = _trainer(client, db_session)
    _row(db_session, other_id, time="10:00")

    assert (
        conflicting_sessions(
            db_session, trainer_id, [(DAY, "10:00")], duration_minutes=60
        )
        == []
    )


def test_sessions_crossing_midnight_block_the_next_morning(client, db_session):
    trainer_id, _ = _trainer(client, db_session)
    late = _row(db_session, trainer_id, time="23:30", minutes=90)

    early = conflicting_sessions(
        db_session, trainer_id, [(NEXT_DAY, "00:30")], duration_minutes=30
    )
    later = conflicting_sessions(
        db_session, trainer_id, [(NEXT_DAY, "01:00")], duration_minutes=30
    )
    before_midnight = conflicting_sessions(
        db_session, trainer_id, [(DAY, "23:00")], duration_minutes=60
    )

    assert [c.id for c in early] == [late]
    assert later == []
    assert [c.id for c in before_midnight] == [late]


def test_excluded_ids_are_skipped(client, db_session):
    trainer_id, _ = _trainer(client, db_session)
    own = _row(db_session, trainer_id, time="10:00")
    other = _row(db_session, trainer_id, time="10:30", minutes=30)

    found = conflicting_sessions(
        db_session,
        trainer_id,
        [(DAY, "10:00")],
        duration_minutes=90,
        exclude_ids=[own],
    )

    assert [c.id for c in found] == [other]


def test_multiple_slots_are_checked_together(client, db_session):
    trainer_id, _ = _trainer(client, db_session)
    first = _row(db_session, trainer_id, time="10:00")
    second = _row(db_session, trainer_id, day=NEXT_DAY, time="10:00")

    found = conflicting_sessions(
        db_session,
        trainer_id,
        [(DAY, "10:30"), (NEXT_DAY, "09:30"), ("2031-03-12", "10:00")],
        duration_minutes=45,
    )

    assert sorted(c.id for c in found) == sorted([first, second])


def test_malformed_rows_and_inputs_are_ignored(client, db_session):
    """형식이 깨진 옛 행이 판정 전체를 500 으로 만들지 않는다."""
    trainer_id, _ = _trainer(client, db_session)
    _row(db_session, trainer_id, time="오전")

    assert (
        conflicting_sessions(
            db_session, trainer_id, [(DAY, "10:00")], duration_minutes=60
        )
        == []
    )
    assert conflicting_sessions(db_session, trainer_id, [("not-a-day", "10:00")]) == []
    assert conflicting_sessions(db_session, trainer_id, []) == []


def test_ensure_no_overlap_raises_with_conflicts_and_custom_message(
    client, db_session
):
    trainer_id, _ = _trainer(client, db_session)
    existing = _row(db_session, trainer_id, time="10:00")

    with pytest.raises(ScheduleOverlap) as caught:
        ensure_no_overlap(
            db_session,
            trainer_id,
            date=DAY,
            time="10:15",
            duration_minutes=15,
            message="겹칩니다",
        )

    assert str(caught.value) == "겹칩니다"
    assert [c.id for c in caught.value.conflicts] == [existing]
    detail = trainer_schedule_service.overlap_detail(caught.value)
    assert detail["code"] == SCHEDULE_OVERLAP_CODE
    assert detail["conflicts"][0]["id"] == existing
    hidden = trainer_schedule_service.overlap_detail(caught.value, include_conflicts=False)
    assert "conflicts" not in hidden
    # 비어 있으면 조용히 지나간다.
    ensure_no_overlap(
        db_session, trainer_id, date=DAY, time="11:00", duration_minutes=30
    )


# ---- 단건 생성 ----


def test_create_rejects_a_partial_overlap(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    first = _create(client, token, time="10:00", duration_minutes=60)
    assert first.status_code == 201, first.text

    second = _create(client, token, time="10:30", duration_minutes=30)

    _assert_overlap(second, conflict_ids=[first.json()["id"]])
    rows = (
        db_session.query(TrainerSchedule)
        .filter(TrainerSchedule.trainer_id == trainer_id)
        .all()
    )
    assert len(rows) == 1


def test_create_allows_back_to_back_sessions(client, db_session):
    _, token = _trainer(client, db_session)
    assert _create(client, token, time="10:00").status_code == 201
    assert _create(client, token, time="11:00").status_code == 201
    assert _create(client, token, time="09:00").status_code == 201


def test_create_is_allowed_over_a_cancelled_session(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    _row(
        db_session,
        trainer_id,
        time="10:00",
        status=trainer_common_service.SCHEDULE_CANCELLED,
    )

    assert _create(client, token, time="10:00").status_code == 201


def test_create_retry_with_same_key_is_not_an_overlap(client, db_session):
    """같은 키의 재시도는 자기 자신과 겹친다고 거절되지 않고 첫 결과를 받는다."""
    _, token = _trainer(client, db_session)
    key = f"overlap-{uuid4().hex[:10]}"

    first = _create(client, token, client_request_id=key)
    retry = _create(client, token, client_request_id=key)

    assert first.status_code == 201, first.text
    assert retry.status_code == 201, retry.text
    assert retry.json()["id"] == first.json()["id"]


def test_create_with_new_key_at_the_same_time_is_an_overlap(client, db_session):
    _, token = _trainer(client, db_session)
    assert _create(client, token, client_request_id=uuid4().hex).status_code == 201

    _assert_overlap(_create(client, token, client_request_id=uuid4().hex))


def test_create_overlap_sends_no_member_notification(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    member_id, _ = _member(client, db_session, trainer_id)
    assert _create(client, token, time="10:00").status_code == 201

    rejected = _create(client, token, time="10:30", member_id=member_id)

    _assert_overlap(rejected)
    assert (
        db_session.query(Notification)
        .filter(Notification.user_id == member_id)
        .count()
        == 0
    )


# ---- 수정 ----


def test_update_rejects_moving_into_another_session(client, db_session):
    _, token = _trainer(client, db_session)
    blocker = _create(client, token, time="10:00").json()
    moving = _create(client, token, time="13:00").json()

    response = client.put(
        f"/v1/trainer/schedule/{moving['id']}",
        json={"time": "10:45"},
        headers=_auth(token),
    )

    _assert_overlap(response, conflict_ids=[blocker["id"]])
    # 거절된 수정은 아무것도 바꾸지 않는다.
    db_session.expire_all()
    assert db_session.get(TrainerSchedule, moving["id"]).time == "13:00"


def test_update_rejects_extending_into_the_next_session(client, db_session):
    _, token = _trainer(client, db_session)
    first = _create(client, token, time="10:00").json()
    following = _create(client, token, time="11:00").json()

    response = client.put(
        f"/v1/trainer/schedule/{first['id']}",
        json={"duration_minutes": 90},
        headers=_auth(token),
    )

    _assert_overlap(response, conflict_ids=[following["id"]])


def test_update_rejects_moving_to_another_day_with_a_session(client, db_session):
    _, token = _trainer(client, db_session)
    blocker = _create(client, token, date=NEXT_DAY, time="10:00").json()
    moving = _create(client, token, time="10:00").json()

    response = client.put(
        f"/v1/trainer/schedule/{moving['id']}",
        json={"date": NEXT_DAY},
        headers=_auth(token),
    )

    _assert_overlap(response, conflict_ids=[blocker["id"]])


def test_update_does_not_conflict_with_itself(client, db_session):
    _, token = _trainer(client, db_session)
    session = _create(client, token, time="10:00").json()

    longer = client.put(
        f"/v1/trainer/schedule/{session['id']}",
        json={"duration_minutes": 120},
        headers=_auth(token),
    )
    shifted = client.put(
        f"/v1/trainer/schedule/{session['id']}",
        json={"time": "10:30"},
        headers=_auth(token),
    )

    assert longer.status_code == 200, longer.text
    assert shifted.status_code == 200, shifted.text
    assert shifted.json()["time"] == "10:30"


def test_update_of_other_fields_skips_the_overlap_check(client, db_session):
    """시간을 건드리지 않는 수정은 이미 겹쳐 있던 옛 데이터라도 막지 않는다."""
    trainer_id, token = _trainer(client, db_session)
    _row(db_session, trainer_id, time="10:00")
    legacy = _row(db_session, trainer_id, time="10:30")

    response = client.put(
        f"/v1/trainer/schedule/{legacy}",
        json={"note": "메모만 바꾼다"},
        headers=_auth(token),
    )

    assert response.status_code == 200, response.text


def test_update_to_adjacent_time_is_allowed(client, db_session):
    _, token = _trainer(client, db_session)
    _create(client, token, time="10:00")
    moving = _create(client, token, time="14:00").json()

    response = client.put(
        f"/v1/trainer/schedule/{moving['id']}",
        json={"time": "11:00"},
        headers=_auth(token),
    )

    assert response.status_code == 200, response.text


# ---- 반복 생성·미리보기 ----


def _recurring(**over) -> dict:
    body = {
        "date": DAY,  # 2031-03-10 은 월요일
        "time": "10:30",
        "weekdays": [1],
        "count": 3,
        "client_name": "겹침 회원",
        "type": "1:1 PT",
        "duration_minutes": 60,
    }
    body.update(over)
    return body


def test_recurring_create_rejects_a_partial_overlap(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    blocker = _row(db_session, trainer_id, day="2031-03-17", time="10:00")

    response = client.post(
        "/v1/trainer/schedule/recurring", json=_recurring(), headers=_auth(token)
    )

    _assert_overlap(response, conflict_ids=[blocker])
    assert (
        db_session.query(TrainerSchedule)
        .filter(TrainerSchedule.trainer_id == trainer_id)
        .count()
        == 1
    )


def test_recurring_preview_uses_the_duration(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    blocker = _row(db_session, trainer_id, day="2031-03-17", time="11:00")

    short = client.post(
        "/v1/trainer/schedule/recurring/preview",
        json=_recurring(duration_minutes=30),
        headers=_auth(token),
    )
    long = client.post(
        "/v1/trainer/schedule/recurring/preview",
        json=_recurring(duration_minutes=60),
        headers=_auth(token),
    )

    assert short.status_code == 200, short.text
    assert short.json()["conflicts"] == []
    assert [c["id"] for c in long.json()["conflicts"]] == [blocker]


def test_recurring_create_without_overlap_succeeds(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    _row(db_session, trainer_id, day="2031-03-17", time="09:30", minutes=60)

    response = client.post(
        "/v1/trainer/schedule/recurring", json=_recurring(), headers=_auth(token)
    )

    assert response.status_code == 201, response.text
    assert len(response.json()) == 3


# ---- 프로그램 + 일정 추가 ----


def _program_body(**over) -> dict:
    body = {
        "name": "겹침 프로그램",
        "sessions": [
            {
                "id": "session-1",
                "name": "세션 A",
                "exercises": [{"id": "ex-1", "name": "스쿼트", "sets": 3}],
            }
        ],
        "date": DAY,
        "time": "10:30",
        "duration_minutes": 60,
        "client_name": "겹침 회원",
    }
    body.update(over)
    return body


def test_program_schedule_rejects_overlap_with_another_member(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    member_id, _ = _member(client, db_session, trainer_id)
    blocker = _row(db_session, trainer_id, time="10:00")

    response = client.post(
        f"/v1/trainer/clients/{member_id}/program-schedule",
        json=_program_body(),
        headers=_auth(token),
    )

    _assert_overlap(response, conflict_ids=[blocker])
    # 배정도 남지 않는다 — 둘 다 되거나 둘 다 안 된다(#1580).
    assert (
        db_session.query(TrainerRoutine)
        .filter(TrainerRoutine.member_id == member_id)
        .count()
        == 0
    )


def test_program_schedule_attaching_to_the_members_session_is_not_an_overlap(
    client, db_session
):
    """같은 회원의 겹치는 예정 세션에는 붙인다 — 새 일정을 만들지 않으니 겹침이 아니다."""
    trainer_id, token = _trainer(client, db_session)
    member_id, _ = _member(client, db_session, trainer_id)
    own = _create(client, token, time="10:00", member_id=member_id).json()

    response = client.post(
        f"/v1/trainer/clients/{member_id}/program-schedule",
        json=_program_body(),
        headers=_auth(token),
    )

    assert response.status_code == 201, response.text
    assert response.json()["attached_to_existing"] is True
    assert response.json()["session"]["id"] == own["id"]


# ---- 예약 슬롯 ----


def _open_slot(client, token: str, *, day: str = DAY, time: str = "10:00", **over):
    body = {
        "starts_at": _kst(day, time).isoformat(),
        "session_type": "1:1 PT",
    }
    body.update(over)
    return client.post(
        "/v1/trainer/reservation-slots", json=body, headers=_auth(token)
    )


def test_slot_cannot_open_over_a_session(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    blocker = _row(db_session, trainer_id, time="10:30", minutes=30)

    response = _open_slot(client, token, time="10:00")

    _assert_overlap(response, conflict_ids=[blocker])
    assert (
        db_session.query(TrainerReservationSlot)
        .filter(TrainerReservationSlot.trainer_id == trainer_id)
        .count()
        == 0
    )


def test_slot_uses_its_default_duration_for_the_check(client, db_session):
    """상담 자리는 기본 30분 — 10:30 일정 앞의 10:00 상담 자리는 열린다."""
    trainer_id, token = _trainer(client, db_session)
    _row(db_session, trainer_id, time="10:30")

    consult = _open_slot(client, token, time="10:00", session_type="상담")
    pt = _open_slot(client, token, time="10:00", session_type="1:1 PT")

    assert consult.status_code == 201, consult.text
    _assert_overlap(pt)


def test_slot_move_into_a_session_is_rejected(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    blocker = _row(db_session, trainer_id, time="14:00")
    slot = _open_slot(client, token, time="10:00").json()

    response = client.put(
        f"/v1/trainer/reservation-slots/{slot['id']}",
        json={"starts_at": _kst(DAY, "13:30").isoformat()},
        headers=_auth(token),
    )

    _assert_overlap(response, conflict_ids=[blocker])
    db_session.expire_all()
    stored = db_session.get(TrainerReservationSlot, slot["id"])
    assert stored.starts_at.astimezone(SEOUL).strftime("%H:%M") == "10:00"


def test_slot_extension_into_a_session_is_rejected(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    _row(db_session, trainer_id, time="11:00")
    slot = _open_slot(client, token, time="10:00").json()

    response = client.put(
        f"/v1/trainer/reservation-slots/{slot['id']}",
        json={"duration_minutes": 90},
        headers=_auth(token),
    )

    _assert_overlap(response)


def test_reopening_a_closed_slot_over_a_session_is_rejected(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    slot = _open_slot(client, token, time="10:00").json()
    closed = client.delete(
        f"/v1/trainer/reservation-slots/{slot['id']}", headers=_auth(token)
    )
    assert closed.status_code == 200, closed.text
    _row(db_session, trainer_id, time="10:00")

    response = client.put(
        f"/v1/trainer/reservation-slots/{slot['id']}",
        json={"is_closed": False},
        headers=_auth(token),
    )

    _assert_overlap(response)


def test_moving_a_closed_slot_is_not_checked(client, db_session):
    """닫힌 자리는 회원이 잡을 수 없으니 옮겨 둬도 이중 예약이 아니다."""
    trainer_id, token = _trainer(client, db_session)
    slot = _open_slot(client, token, time="10:00").json()
    client.delete(f"/v1/trainer/reservation-slots/{slot['id']}", headers=_auth(token))
    _row(db_session, trainer_id, time="14:00")

    response = client.put(
        f"/v1/trainer/reservation-slots/{slot['id']}",
        json={"starts_at": _kst(DAY, "14:00").isoformat()},
        headers=_auth(token),
    )

    assert response.status_code == 200, response.text


def test_booked_slot_moves_without_conflicting_with_its_own_session(
    client, db_session
):
    trainer_id, token = _trainer(client, db_session)
    _, member_token = _member(client, db_session, trainer_id)
    slot = _open_slot(client, token, time="10:00").json()
    booked = client.post(
        "/v1/reservations", json={"slot_id": slot["id"]}, headers=_auth(member_token)
    )
    assert booked.status_code == 201, booked.text

    moved = client.put(
        f"/v1/trainer/reservation-slots/{slot['id']}",
        json={"starts_at": _kst(DAY, "10:30").isoformat()},
        headers=_auth(token),
    )

    assert moved.status_code == 200, moved.text
    db_session.expire_all()
    schedule = db_session.get(TrainerSchedule, booked.json()["schedule_id"])
    assert schedule.time == "10:30"


# ---- 회원 예약 ----


def test_reserve_rejects_a_slot_the_trainer_has_since_filled(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    member_id, member_token = _member(client, db_session, trainer_id)
    slot = _open_slot(client, token, time="10:00").json()
    # 자리를 연 뒤 트레이너가 그 시간에 다른 일정을 잡았다.
    assert _create(client, token, time="10:30", duration_minutes=30).status_code == 201

    response = client.post(
        "/v1/reservations", json={"slot_id": slot["id"]}, headers=_auth(member_token)
    )

    assert response.status_code == 409, response.text
    detail = response.json()["detail"]
    assert detail["code"] == SCHEDULE_OVERLAP_CODE
    assert detail["message"]
    # 회원에게는 트레이너의 다른 일정이 가지 않는다.
    assert "conflicts" not in detail
    db_session.expire_all()
    assert db_session.get(TrainerReservationSlot, slot["id"]).remaining == 1
    assert (
        db_session.query(TrainerReservation)
        .filter(TrainerReservation.member_id == member_id)
        .count()
        == 0
    )


def test_reserve_succeeds_next_to_another_session(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    _, member_token = _member(client, db_session, trainer_id)
    slot = _open_slot(client, token, time="10:00").json()
    assert _create(client, token, time="11:00").status_code == 201

    response = client.post(
        "/v1/reservations", json={"slot_id": slot["id"]}, headers=_auth(member_token)
    )

    assert response.status_code == 201, response.text


def test_two_open_slots_at_the_same_time_cannot_both_be_booked(client, db_session):
    """겹치는 자리 둘이 열려 있어도 두 번째 예약은 첫 예약의 일정과 겹쳐 막힌다."""
    trainer_id, token = _trainer(client, db_session)
    _, first_token = _member(client, db_session, trainer_id)
    first_slot = _open_slot(client, token, time="10:00").json()
    second_slot = _open_slot(client, token, time="10:30").json()
    # 두 번째 회원은 다른 트레이너 담당일 수 없으니 같은 트레이너의 담당을 하나 더 둔다.
    _, second_token = _member(client, db_session, trainer_id)

    first = client.post(
        "/v1/reservations",
        json={"slot_id": first_slot["id"]},
        headers=_auth(first_token),
    )
    second = client.post(
        "/v1/reservations",
        json={"slot_id": second_slot["id"]},
        headers=_auth(second_token),
    )

    assert first.status_code == 201, first.text
    assert second.status_code == 409, second.text
    assert second.json()["detail"]["code"] == SCHEDULE_OVERLAP_CODE


# ---- 상담 승인 ----


def _consultation(db_session, trainer_id: str, member_id: str, slot_id: str) -> str:
    """회원이 그 자리를 골라 넣은 대기 중 상담 요청."""
    from app.services import reservation_service

    slot = db_session.get(TrainerReservationSlot, slot_id)
    reservation_service.hold_slot_for_consultation(
        db_session,
        trainer_id,
        slot_id,
        after=slot.starts_at - timedelta(days=1),
    )
    request_id = f"consult-{uuid4().hex[:12]}"
    db_session.add(
        ConsultationRequest(
            id=request_id,
            member_id=member_id,
            trainer_id=trainer_id,
            target_type="trainer",
            exercise_goal="weight_loss",
            health_purpose_type="general",
            slot_id=slot_id,
            preferred_date=slot.starts_at.astimezone(SEOUL).date().isoformat(),
            preferred_time_slot=slot.starts_at.astimezone(SEOUL).strftime("%H:%M"),
            message="상담 부탁드립니다.",
            status="pending",
        )
    )
    db_session.commit()
    return request_id


def test_accept_rejects_a_slot_the_trainer_has_since_filled(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    member_id, _ = _member(client, db_session)
    slot = _open_slot(client, token, time="10:00").json()
    request_id = _consultation(db_session, trainer_id, member_id, slot["id"])
    blocker = _create(client, token, time="10:30", duration_minutes=30).json()

    response = client.post(
        f"/v1/trainer/consultations/{request_id}/accept",
        json={},
        headers=_auth(token),
    )

    _assert_overlap(response, conflict_ids=[blocker["id"]])
    # 반쪽 상태가 남지 않는다 — 요청은 그대로 대기, 담당 링크·일정도 없다.
    db_session.expire_all()
    assert db_session.get(ConsultationRequest, request_id).status == "pending"
    assert (
        db_session.query(TrainerClient)
        .filter(TrainerClient.member_id == member_id)
        .count()
        == 0
    )
    assert (
        db_session.query(TrainerSchedule)
        .filter(TrainerSchedule.member_id == member_id)
        .count()
        == 0
    )


def test_accept_succeeds_once_the_blocking_session_is_moved(client, db_session):
    trainer_id, token = _trainer(client, db_session)
    member_id, _ = _member(client, db_session)
    slot = _open_slot(client, token, time="10:00").json()
    request_id = _consultation(db_session, trainer_id, member_id, slot["id"])
    blocker = _create(client, token, time="10:30", duration_minutes=30).json()
    url = f"/v1/trainer/consultations/{request_id}/accept"
    assert client.post(url, json={}, headers=_auth(token)).status_code == 409

    moved = client.put(
        f"/v1/trainer/schedule/{blocker['id']}",
        json={"time": "15:00"},
        headers=_auth(token),
    )
    assert moved.status_code == 200, moved.text
    accepted = client.post(url, json={}, headers=_auth(token))

    assert accepted.status_code == 200, accepted.text
    assert accepted.json()["schedule_created"] is True
