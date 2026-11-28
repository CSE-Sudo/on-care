"""회원 탈퇴와 트레이너 일정 — 남은 일정은 취소되고, 지난 일정은 이름·메모가 지워진다. (#3341)

회원 행을 지우면 `trainer_schedule.member_id` 는 NULL 이 될 뿐 행과 `client_name`·
메모는 남는다. 정리하지 않으면 트레이너 스케줄에 탈퇴한 회원의 실명이 예정 일정으로
계속 뜬다. 여기서 보는 것:

  * 서비스 — 탈퇴가 거둘 일정의 기준(시작 전 `예정`, 트레이너 무관, 수락된 상담 포함,
    회원 예약이 만든 일정 제외)과 정리 결과(취소 기록, 이름·메모 지움).
  * API — `DELETE /users/me` 뒤 트레이너 스케줄 응답, 예약 좌석, 탈퇴 알림 한 건.
"""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select, text

from app.core import clock
from app.core.security import create_access_token, hash_password
from app.models.models import (
    ConsultationRequest,
    Notification,
    TrainerClient,
    TrainerReservation,
    TrainerReservationSlot,
    TrainerSchedule,
    User,
)
from app.services import notification_templates as nt
from app.services.trainer import _common as trainer_common_service

PASSWORD = "withdraw-pw-1234"
MEMBER_NAME = "탈퇴할 회원"
NOTE = "무릎 통증 있음 — 스쿼트 깊이 조절"


def _h(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@dataclass(frozen=True)
class Pair:
    trainer_id: str
    other_trainer_id: str
    member_id: str
    other_member_id: str
    headers: dict[str, str]
    other_headers: dict[str, str]
    member_headers: dict[str, str]


@pytest.fixture()
def pair(db_session) -> Iterator[Pair]:
    """담당 중인 (트레이너, 회원) 한 쌍과, 담당이 아닌 트레이너·다른 회원 하나씩."""
    suffix = uuid4().hex[:10]
    trainer_id = f"withdraw-trainer-{suffix}"
    other_trainer_id = f"withdraw-other-trainer-{suffix}"
    member_id = f"withdraw-member-{suffix}"
    other_member_id = f"withdraw-other-member-{suffix}"

    def user(user_id: str, name: str, role: str) -> User:
        return User(
            id=user_id,
            email=f"{user_id}@oncare.com",
            name=name,
            hashed_password=hash_password(PASSWORD),
            role=role,
        )

    db_session.add_all(
        [
            user(trainer_id, "박코치", "trainer"),
            user(other_trainer_id, "최코치", "trainer"),
            user(member_id, MEMBER_NAME, "member"),
            user(other_member_id, "남는 회원", "member"),
        ]
    )
    db_session.flush()
    db_session.add_all(
        [
            TrainerClient(
                id=f"tc-{uuid4().hex[:12]}",
                trainer_id=trainer_id,
                member_id=linked_member,
                active=True,
                data_consent_at=clock.now(),
            )
            for linked_member in (member_id, other_member_id)
        ]
    )
    db_session.commit()
    ids = [trainer_id, other_trainer_id, member_id, other_member_id]
    try:
        yield Pair(
            trainer_id=trainer_id,
            other_trainer_id=other_trainer_id,
            member_id=member_id,
            other_member_id=other_member_id,
            headers=_h(create_access_token(trainer_id)),
            other_headers=_h(create_access_token(other_trainer_id)),
            member_headers=_h(create_access_token(member_id)),
        )
    finally:
        db_session.rollback()
        db_session.expire_all()
        db_session.execute(
            text("DELETE FROM trainer_reservations WHERE member_id = ANY(:ids)"),
            {"ids": ids},
        )
        db_session.execute(
            text("DELETE FROM users WHERE id = ANY(:ids)"), {"ids": ids}
        )
        db_session.commit()


def _day(offset: int) -> str:
    return (clock.today() + timedelta(days=offset)).isoformat()


def _session(
    db_session,
    p: Pair,
    *,
    day: str,
    time: str = "10:00",
    status: str = "예정",
    trainer_id: str | None = None,
    member_id: str | None = None,
    type_: str = "1:1 PT",
    consultation_id: str | None = None,
) -> str:
    """일정 행을 바로 넣는다 — 지난 날짜도 만들 수 있게 API 를 거치지 않는다."""
    session_id = f"sched-{uuid4().hex[:12]}"
    db_session.add(
        TrainerSchedule(
            id=session_id,
            trainer_id=trainer_id or p.trainer_id,
            member_id=member_id or p.member_id,
            consultation_id=consultation_id,
            client_name=MEMBER_NAME,
            date=day,
            time=time,
            type=type_,
            duration_minutes=50,
            status=status,
            note=NOTE,
        )
    )
    db_session.commit()
    return session_id


def _booking(db_session, p: Pair, *, days: int = 3) -> tuple[str, str]:
    """회원 예약 한 건과 그 예약이 만든 일정. (slot_id, schedule_id)"""
    starts_at = datetime.now(timezone.utc) + timedelta(days=days)
    slot = TrainerReservationSlot(
        id=f"slot-{uuid4().hex[:12]}",
        trainer_id=p.trainer_id,
        starts_at=starts_at,
        duration_minutes=60,
        capacity=1,
        remaining=0,
        session_type="1:1 PT",
    )
    db_session.add(slot)
    db_session.commit()
    schedule_id = _session(db_session, p, day=_day(days), time="15:00")
    db_session.add(
        TrainerReservation(
            id=f"res-{uuid4().hex[:12]}",
            member_id=p.member_id,
            slot_id=slot.id,
            schedule_id=schedule_id,
            status="booked",
        )
    )
    db_session.commit()
    return slot.id, schedule_id


def _accepted_consultation(db_session, p: Pair, *, day: str) -> str:
    """담당이 아닌 트레이너가 수락한 상담과 그 상담 일정. 일정 id 를 준다."""
    consultation_id = f"consult-{uuid4().hex[:12]}"
    db_session.add(
        ConsultationRequest(
            id=consultation_id,
            member_id=p.member_id,
            target_type="trainer",
            trainer_id=p.other_trainer_id,
            exercise_goal="fitness",
            health_purpose_type="general",
            preferred_date=day,
            preferred_time_slot="09:00",
            status="accepted",
        )
    )
    db_session.commit()
    return _session(
        db_session,
        p,
        day=day,
        time="09:00",
        trainer_id=p.other_trainer_id,
        type_="상담",
        consultation_id=consultation_id,
    )


def _withdraw(client, p: Pair) -> None:
    r = client.request(
        "DELETE",
        "/v1/users/me",
        json={"current_password": PASSWORD},
        headers=p.member_headers,
    )
    assert r.status_code == 200, r.text


def _schedule(client, headers: dict[str, str], day: str) -> dict[str, dict]:
    r = client.get("/v1/trainer/schedule", params={"date": day}, headers=headers)
    assert r.status_code == 200, r.text
    return {row["id"]: row for row in r.json()}


def _row(db_session, session_id: str) -> TrainerSchedule | None:
    db_session.expire_all()
    return db_session.get(TrainerSchedule, session_id)


def _notices(db_session, user_id: str, template: str) -> list[Notification]:
    db_session.expire_all()
    return list(
        db_session.scalars(
            select(Notification).where(
                Notification.user_id == user_id,
                Notification.template == template,
            )
        ).all()
    )


# --------------------------------------------------------------------------
# 서비스 — 거둘 일정의 기준
# --------------------------------------------------------------------------


def _to_cancel(db_session, member_id: str) -> set[str]:
    db_session.expire_all()
    return {
        s.id
        for s in trainer_common_service.sessions_cancelled_on_withdrawal(
            db_session, member_id
        )
    }


def test_only_sessions_that_have_not_started_are_cancelled(db_session, pair):
    """시작 전인 `예정` 만 — 지난 일정과 이미 끝난 일정은 기록으로 남는다."""
    tomorrow = _session(db_session, pair, day=_day(1))
    next_week = _session(db_session, pair, day=_day(7), time="19:30")
    _session(db_session, pair, day=_day(-1))
    _session(db_session, pair, day=_day(-3), status="완료")
    _session(db_session, pair, day=_day(2), status="취소")
    _session(db_session, pair, day=_day(2), time="11:00", status="노쇼")

    assert _to_cancel(db_session, pair.member_id) == {tomorrow, next_week}


def test_todays_session_counts_only_before_it_starts(db_session, pair):
    """오늘 일정은 시작 시각으로 가른다. 읽을 수 없는 시각은 시작한 것으로 본다."""
    now = clock.now()
    started = _session(db_session, pair, day=_day(0), time="00:00")
    unreadable = _session(db_session, pair, day=_day(0), time="")
    cancelled = _to_cancel(db_session, pair.member_id)

    assert started not in cancelled
    assert unreadable not in cancelled
    if now.hour < 23:
        later = _session(db_session, pair, day=_day(0), time="23:59")
        assert later in _to_cancel(db_session, pair.member_id)


def test_sessions_with_any_trainer_are_cancelled(db_session, pair):
    """담당이 아닌 트레이너와 잡힌 일정도 거둔다 — 회원이 사라진다."""
    mine = _session(db_session, pair, day=_day(1))
    theirs = _session(
        db_session, pair, day=_day(2), trainer_id=pair.other_trainer_id
    )

    assert _to_cancel(db_session, pair.member_id) == {mine, theirs}


def test_accepted_consultation_is_cancelled_too(db_session, pair):
    """담당 해제는 상담 일정을 남기지만(#2584), 탈퇴는 상담할 사람이 없다."""
    consult = _accepted_consultation(db_session, pair, day=_day(2))

    assert _to_cancel(db_session, pair.member_id) == {consult}
    assert (
        trainer_common_service.sessions_cancelled_on_detach(
            db_session, pair.other_trainer_id, pair.member_id
        )
        == []
    )


def test_reservation_made_session_is_left_to_the_reservation_cleanup(
    db_session, pair
):
    """회원 예약이 만든 일정은 세지 않는다 — 예약 정리가 맡고, 미리보기도 따로 센다."""
    _booking(db_session, pair)
    direct = _session(db_session, pair, day=_day(1))

    assert _to_cancel(db_session, pair.member_id) == {direct}


def test_other_members_sessions_are_untouched(db_session, pair):
    mine = _session(db_session, pair, day=_day(1))
    theirs = _session(
        db_session, pair, day=_day(1), time="12:00", member_id=pair.other_member_id
    )

    assert _to_cancel(db_session, pair.member_id) == {mine}
    assert _to_cancel(db_session, pair.other_member_id) == {theirs}


# --------------------------------------------------------------------------
# 서비스 — 정리 결과
# --------------------------------------------------------------------------


def test_clearing_cancels_upcoming_and_records_why(db_session, pair):
    upcoming = _session(db_session, pair, day=_day(1))
    before = datetime.now(timezone.utc)

    count = trainer_common_service.clear_sessions_on_withdrawal(
        db_session, pair.member_id
    )
    db_session.commit()

    row = _row(db_session, upcoming)
    assert count == 1
    assert row.status == trainer_common_service.SCHEDULE_CANCELLED
    assert row.cancellation_source == "member"
    assert row.cancellation_reason == trainer_common_service.WITHDRAW_CANCEL_REASON
    assert row.cancelled_at is not None
    assert row.cancelled_at >= before - timedelta(seconds=1)


def test_clearing_erases_name_and_note_on_every_row(db_session, pair):
    """취소한 일정도, 지난 일정도 — 남는 행에는 이름과 메모가 없다."""
    ids = [
        _session(db_session, pair, day=_day(1)),
        _session(db_session, pair, day=_day(-1)),
        _session(db_session, pair, day=_day(-5), status="완료"),
        _session(db_session, pair, day=_day(-6), status="노쇼"),
        _session(db_session, pair, day=_day(2), trainer_id=pair.other_trainer_id),
    ]

    trainer_common_service.clear_sessions_on_withdrawal(db_session, pair.member_id)
    db_session.commit()

    for session_id in ids:
        row = _row(db_session, session_id)
        assert row.client_name == trainer_common_service.WITHDRAWN_CLIENT_NAME
        assert row.note == ""


def test_clearing_unlinks_the_consultation_request(db_session, pair):
    """상담 요청과의 연결을 먼저 끊는다 — 남겨 두면 회원 삭제가 FK 에서 막힌다."""
    consult = _accepted_consultation(db_session, pair, day=_day(2))

    trainer_common_service.clear_sessions_on_withdrawal(db_session, pair.member_id)
    db_session.commit()

    assert _row(db_session, consult).consultation_id is None


def test_withdrawal_succeeds_with_a_past_consultation_session(
    client, db_session, pair
):
    """끝난 상담 일정만 있어도 탈퇴가 된다 — 이름·메모를 고친 행이 삭제를 막지 않는다."""
    day = _day(-3)
    consult = _accepted_consultation(db_session, pair, day=day)

    _withdraw(client, pair)

    row = _schedule(client, pair.other_headers, day)[consult]
    assert row["status"] == "예정"
    assert row["client_name"] == "탈퇴 회원"
    assert row["consultation"] is None


def test_clearing_keeps_how_past_sessions_ended(db_session, pair):
    """지난 수업의 결말은 그대로다 — 완료를 취소로 덮지 않는다."""
    done = _session(db_session, pair, day=_day(-5), status="완료")
    no_show = _session(db_session, pair, day=_day(-6), status="노쇼")
    past_upcoming = _session(db_session, pair, day=_day(-1))

    count = trainer_common_service.clear_sessions_on_withdrawal(
        db_session, pair.member_id
    )
    db_session.commit()

    assert count == 0
    assert _row(db_session, done).status == "완료"
    assert _row(db_session, no_show).status == "노쇼"
    assert _row(db_session, past_upcoming).status == "예정"
    assert _row(db_session, past_upcoming).cancelled_at is None


def test_clearing_leaves_other_members_rows_alone(db_session, pair):
    theirs = _session(
        db_session, pair, day=_day(1), member_id=pair.other_member_id
    )

    trainer_common_service.clear_sessions_on_withdrawal(db_session, pair.member_id)
    db_session.commit()

    row = _row(db_session, theirs)
    assert row.status == "예정"
    assert row.client_name == MEMBER_NAME
    assert row.note == NOTE


def test_clearing_with_no_sessions_is_a_no_op(db_session, pair):
    assert (
        trainer_common_service.clear_sessions_on_withdrawal(
            db_session, pair.member_id
        )
        == 0
    )


# --------------------------------------------------------------------------
# API — DELETE /users/me
# --------------------------------------------------------------------------


def test_withdrawal_cancels_upcoming_sessions_on_the_trainer_schedule(
    client, db_session, pair
):
    day = _day(2)
    upcoming = _session(db_session, pair, day=day)

    _withdraw(client, pair)

    row = _schedule(client, pair.headers, day)[upcoming]
    assert row["status"] == "취소"
    assert row["cancellation_source"] == "member"
    assert row["cancellation_reason"] == "회원 탈퇴"
    assert row["member_id"] is None


def test_withdrawal_hides_name_and_note_on_the_trainer_schedule(
    client, db_session, pair
):
    """예정이었던 일정도 지난 일정도 실명과 메모를 싣지 않는다."""
    future, past = _day(2), _day(-2)
    upcoming = _session(db_session, pair, day=future)
    done = _session(db_session, pair, day=past, status="완료")

    _withdraw(client, pair)

    for day, session_id in ((future, upcoming), (past, done)):
        row = _schedule(client, pair.headers, day)[session_id]
        assert row["client_name"] == "탈퇴 회원"
        assert row["note"] == ""
        assert MEMBER_NAME not in str(row)
        assert NOTE not in str(row)
    assert _schedule(client, pair.headers, past)[done]["status"] == "완료"


def test_withdrawal_cancels_an_accepted_consultation_with_another_trainer(
    client, db_session, pair
):
    day = _day(2)
    consult = _accepted_consultation(db_session, pair, day=day)

    _withdraw(client, pair)

    row = _schedule(client, pair.other_headers, day)[consult]
    assert row["status"] == "취소"
    assert row["client_name"] == "탈퇴 회원"
    assert row["consultation"] is None


def test_withdrawal_still_releases_booked_seats(client, db_session, pair):
    """예약이 만든 일정은 지금처럼 예약 정리가 지우고 좌석을 돌려준다."""
    slot_id, schedule_id = _booking(db_session, pair)

    _withdraw(client, pair)

    db_session.expire_all()
    assert db_session.get(TrainerReservationSlot, slot_id).remaining == 1
    assert db_session.get(TrainerSchedule, schedule_id) is None


def test_withdrawal_leaves_other_members_sessions_alone(client, db_session, pair):
    day = _day(2)
    theirs = _session(db_session, pair, day=day, member_id=pair.other_member_id)

    _withdraw(client, pair)

    row = _schedule(client, pair.headers, day)[theirs]
    assert row["status"] == "예정"
    assert row["member_id"] == pair.other_member_id
    assert row["note"] == NOTE


def test_withdrawal_notifies_the_trainer_exactly_once(client, db_session, pair):
    """일정이 여럿 취소돼도 담당 트레이너가 받는 것은 탈퇴 알림 한 건이다."""
    _session(db_session, pair, day=_day(1))
    _session(db_session, pair, day=_day(2))
    _session(db_session, pair, day=_day(3), time="18:00")

    _withdraw(client, pair)

    db_session.expire_all()
    notices = list(
        db_session.scalars(
            select(Notification).where(Notification.user_id == pair.trainer_id)
        ).all()
    )
    assert [n.template for n in notices] == [nt.TRAINER_MEMBER_WITHDRAWN]
    assert _notices(db_session, pair.other_trainer_id, nt.TRAINER_MEMBER_WITHDRAWN) == []


def test_withdrawal_does_not_notify_a_trainer_who_was_not_in_charge(
    client, db_session, pair
):
    """담당이 아닌 트레이너의 일정이 취소돼도 일정별 알림은 만들지 않는다."""
    _session(db_session, pair, day=_day(1), trainer_id=pair.other_trainer_id)

    _withdraw(client, pair)

    db_session.expire_all()
    assert (
        db_session.scalars(
            select(Notification).where(
                Notification.user_id == pair.other_trainer_id
            )
        ).all()
        == []
    )
