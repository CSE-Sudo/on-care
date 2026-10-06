"""트레이너 예약·상담·담당 요청 알림의 이동 목적지. (#2292) DB 필요.

전에는 예약·상담 알림에 날짜도 회원도 남지 않아, 트레이너 앱이 알림을 눌러도
오늘 주 스케줄로만 보냈다. 담당 요청 수락·거절 알림은 상담 종류로 남아 역시
스케줄로 갔다 — 새로 담당이 된 회원을 찾으려면 고객 목록을 다시 뒤져야 했다.

여기서는 알림이 만들어질 때 대상 회원(`subject_id`)·날짜(`target_date`)·종류가
제대로 남는지를 트레이너 알림함 응답으로 확인한다.
"""
from __future__ import annotations

from datetime import datetime, time, timedelta, timezone
from uuid import uuid4

import pytest

from app.core import clock
from app.core.clock import SEOUL
from app.core.security import hash_password
from app.models.models import (
    ConsultationRequest,
    MemberGym,
    Notification,
    Place,
    TrainerClient,
    TrainerClientInvite,
    TrainerProfile,
    TrainerReservation,
    TrainerReservationSlot,
    TrainerSchedule,
    User,
)
from app.services import notification_service

EMAIL_PREFIX = "notitarget-test-"
PLACE_PREFIX = "notitarget-place-"
SLOT_PREFIX = "notitarget-slot-"
PASSWORD = "notitarget-pw-1234"


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
    if user_ids:
        db_session.query(TrainerReservation).filter(
            TrainerReservation.member_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(TrainerSchedule).filter(
            (TrainerSchedule.trainer_id.in_(user_ids))
            | (TrainerSchedule.member_id.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(ConsultationRequest).filter(
            (ConsultationRequest.member_id.in_(user_ids))
            | (ConsultationRequest.trainer_id.in_(user_ids))
            | (ConsultationRequest.decided_by.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(TrainerReservationSlot).filter(
            TrainerReservationSlot.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(TrainerClientInvite).filter(
            (TrainerClientInvite.trainer_id.in_(user_ids))
            | (TrainerClientInvite.member_id.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(TrainerClient).filter(
            (TrainerClient.trainer_id.in_(user_ids))
            | (TrainerClient.member_id.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(Notification).filter(
            Notification.user_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(MemberGym).filter(
            MemberGym.member_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(TrainerProfile).filter(
            TrainerProfile.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(User).filter(User.id.in_(user_ids)).delete(
            synchronize_session=False
        )
    db_session.query(MemberGym).filter(
        MemberGym.gym_id.like(f"{PLACE_PREFIX}%")
    ).delete(synchronize_session=False)
    db_session.query(Place).filter(Place.id.like(f"{PLACE_PREFIX}%")).delete(
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


def _member(client, name: str = "알림 회원") -> tuple[str, str]:
    """회원 계정 하나. (id, token)"""
    email = f"{EMAIL_PREFIX}member-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": name},
    )
    assert response.status_code == 201, response.text
    return response.json()["id"], _login(client, email)


def _trainer(client, db_session) -> tuple[User, str]:
    suffix = uuid4().hex[:10]
    place = Place(
        id=f"{PLACE_PREFIX}{suffix}",
        name="알림 테스트 헬스장",
        category="fitness",
        address="서울",
    )
    db_session.add(place)
    email = f"{EMAIL_PREFIX}trainer-{suffix}@oncare.com"
    trainer = User(
        id=f"notitarget-trainer-{suffix}",
        email=email,
        name="알림 테스트 트레이너",
        hashed_password=hash_password(PASSWORD),
        role="trainer",
        is_active=True,
    )
    db_session.add(trainer)
    db_session.flush()
    db_session.add(TrainerProfile(trainer_id=trainer.id, gym_id=place.id))
    db_session.commit()
    return trainer, _login(client, email)


def _invite(client, trainer_token: str, member_id: str) -> str:
    response = client.post(
        "/v1/trainer/client-invites",
        json={"member_id": member_id, "message": None},
        headers=_auth(trainer_token),
    )
    assert response.status_code == 201, response.text
    return response.json()["id"]


def _accept(client, member_token: str, invite_id: str) -> None:
    response = client.post(
        f"/v1/me/coach/invites/{invite_id}/accept",
        headers=_auth(member_token),
        json={"data_sharing_consent": True},
    )
    assert response.status_code == 200, response.text


def _reject(client, member_token: str, invite_id: str) -> None:
    response = client.post(
        f"/v1/me/coach/invites/{invite_id}/reject", headers=_auth(member_token)
    )
    assert response.status_code == 200, response.text


def _linked_pair(client, db_session) -> tuple[User, str, str, str]:
    """담당으로 연결된 트레이너·회원. (trainer, trainer_token, member_id, member_token)"""
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    _accept(client, member_token, _invite(client, trainer_token, member_id))
    return trainer, trainer_token, member_id, member_token


def _inbox(client, trainer_token: str) -> list[dict]:
    response = client.get("/v1/trainer/notifications", headers=_auth(trainer_token))
    assert response.status_code == 200, response.text
    return response.json()


def _one(client, trainer_token: str, title: str) -> dict:
    rows = [row for row in _inbox(client, trainer_token) if row["title"] == title]
    assert len(rows) == 1, rows
    return rows[0]


def _kst_slot_start(days_ahead: int, at: time) -> datetime:
    """오늘(KST)부터 [days_ahead] 일 뒤 [at] (KST) 의 UTC 시각."""
    local = datetime.combine(clock.today() + timedelta(days=days_ahead), at, SEOUL)
    return local.astimezone(timezone.utc)


def _open_slot_api(client, trainer_token: str, starts_at: datetime) -> str:
    response = client.post(
        "/v1/trainer/reservation-slots",
        headers=_auth(trainer_token),
        json={"starts_at": starts_at.isoformat(), "capacity": 1},
    )
    assert response.status_code == 201, response.text
    return response.json()["id"]


def _reserve(client, member_token: str, slot_id: str) -> str:
    response = client.post(
        "/v1/reservations", headers=_auth(member_token), json={"slot_id": slot_id}
    )
    assert response.status_code == 201, response.text
    return response.json()["id"]


def _open_slot_db(trainer_id: str, starts_at: datetime) -> str:
    """상담용 빈 자리. 상담 신청은 트레이너가 연 자리를 고른다(#1873)."""
    from app.db.session import SessionLocal

    slot = TrainerReservationSlot(
        id=f"{SLOT_PREFIX}{uuid4().hex[:10]}",
        trainer_id=trainer_id,
        starts_at=starts_at,
        duration_minutes=30,
        capacity=1,
        remaining=1,
        session_type="1:1 PT",
    )
    with SessionLocal() as session:
        session.add(slot)
        session.commit()
        return slot.id


def _request_consultation(client, member_token: str, trainer_id: str, starts_at: datetime) -> str:
    payload = {
        "trainer_id": trainer_id,
        "exercise_goal": "weight_loss",
        "health_purpose_type": "general",
        "health_purpose_detail": None,
        "slot_id": _open_slot_db(trainer_id, starts_at),
        "message": "상담 부탁드립니다.",
        "data_sharing_consent": True,
    }
    response = client.post(
        "/v1/consultations", headers=_auth(member_token), json=payload
    )
    assert response.status_code == 201, response.text
    return response.json()["id"]


def _insert(db_session, **fields) -> str:
    row = Notification(
        id=f"noti-{uuid4().hex[:12]}",
        title=fields.pop("title", "옛 알림"),
        body=fields.pop("body", ""),
        read=fields.pop("read", False),
        **fields,
    )
    db_session.add(row)
    db_session.commit()
    return row.id


# ---- 예약 ----


def test_new_reservation_records_member_and_class_date(client, db_session):
    """새 예약 알림은 예약한 회원과 수업 날짜(KST)를 남긴다."""
    _, trainer_token, member_id, member_token = _linked_pair(client, db_session)
    starts_at = _kst_slot_start(5, time(10, 0))
    _reserve(client, member_token, _open_slot_api(client, trainer_token, starts_at))

    row = _one(client, trainer_token, "새 예약이 들어왔어요")
    assert row["category"] == "reservation"
    assert row["subject_id"] == member_id
    assert row["target_date"] == starts_at.astimezone(SEOUL).date().isoformat()


def test_reservation_date_is_the_seoul_date_not_the_utc_date(client, db_session):
    """KST 새벽 수업은 UTC 로는 전날이다 — 알림 날짜는 스케줄과 같은 KST 날짜다."""
    _, trainer_token, member_id, member_token = _linked_pair(client, db_session)
    starts_at = _kst_slot_start(6, time(0, 30))
    assert starts_at.date() != starts_at.astimezone(SEOUL).date()

    _reserve(client, member_token, _open_slot_api(client, trainer_token, starts_at))

    row = _one(client, trainer_token, "새 예약이 들어왔어요")
    expected = (clock.today() + timedelta(days=6)).isoformat()
    assert row["target_date"] == expected


def test_reservation_date_matches_the_trainer_schedule_row(client, db_session):
    """알림 날짜로 스케줄을 열면 그 수업이 그 날짜에 있다."""
    trainer, trainer_token, member_id, member_token = _linked_pair(client, db_session)
    starts_at = _kst_slot_start(3, time(19, 0))
    _reserve(client, member_token, _open_slot_api(client, trainer_token, starts_at))

    row = _one(client, trainer_token, "새 예약이 들어왔어요")
    db_session.expire_all()
    dates = {
        s.date
        for s in db_session.query(TrainerSchedule).filter(
            TrainerSchedule.trainer_id == trainer.id,
            TrainerSchedule.member_id == member_id,
        )
    }
    assert dates == {row["target_date"]}


def test_cancelled_reservation_records_member_and_class_date(client, db_session):
    """예약 취소 알림도 같은 회원·같은 수업 날짜를 가리킨다."""
    _, trainer_token, member_id, member_token = _linked_pair(client, db_session)
    starts_at = _kst_slot_start(4, time(15, 0))
    reservation_id = _reserve(
        client, member_token, _open_slot_api(client, trainer_token, starts_at)
    )

    cancelled = client.delete(
        f"/v1/reservations/{reservation_id}", headers=_auth(member_token)
    )
    assert cancelled.status_code in (200, 204), cancelled.text

    row = _one(client, trainer_token, "예약이 취소됐어요")
    assert row["category"] == "reservation"
    assert row["subject_id"] == member_id
    assert row["target_date"] == starts_at.astimezone(SEOUL).date().isoformat()


def test_two_members_reservations_keep_their_own_targets(client, db_session):
    """두 회원의 예약 알림이 서로의 회원·날짜로 섞이지 않는다."""
    trainer, trainer_token = _trainer(client, db_session)
    first_id, first_token = _member(client, "첫째 회원")
    second_id, second_token = _member(client, "둘째 회원")
    _accept(client, first_token, _invite(client, trainer_token, first_id))
    _accept(client, second_token, _invite(client, trainer_token, second_id))

    first_at = _kst_slot_start(2, time(9, 0))
    second_at = _kst_slot_start(7, time(9, 0))
    _reserve(client, first_token, _open_slot_api(client, trainer_token, first_at))
    _reserve(client, second_token, _open_slot_api(client, trainer_token, second_at))

    rows = [
        row
        for row in _inbox(client, trainer_token)
        if row["title"] == "새 예약이 들어왔어요"
    ]
    targets = {row["subject_id"]: row["target_date"] for row in rows}
    assert targets == {
        first_id: first_at.astimezone(SEOUL).date().isoformat(),
        second_id: second_at.astimezone(SEOUL).date().isoformat(),
    }


# ---- 상담 ----


def test_new_consultation_records_member_and_preferred_date(client, db_session):
    """새 상담 요청 알림은 신청한 회원과 희망 날짜를 남긴다."""
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    starts_at = _kst_slot_start(3, time(11, 0))
    consultation_id = _request_consultation(
        client, member_token, trainer.id, starts_at
    )

    row = _one(client, trainer_token, "새 상담 요청이 도착했어요")
    assert row["category"] == "consultation"
    assert row["subject_id"] == member_id

    db_session.expire_all()
    stored = db_session.get(ConsultationRequest, consultation_id)
    assert row["target_date"] == stored.preferred_date
    assert row["target_date"] == starts_at.astimezone(SEOUL).date().isoformat()


def test_cancelled_consultation_records_member_and_preferred_date(client, db_session):
    """회원이 취소한 상담 알림도 같은 회원·희망 날짜를 가리킨다."""
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    starts_at = _kst_slot_start(4, time(14, 0))
    consultation_id = _request_consultation(
        client, member_token, trainer.id, starts_at
    )

    response = client.delete(
        f"/v1/consultations/{consultation_id}", headers=_auth(member_token)
    )
    assert response.status_code == 200, response.text

    row = _one(client, trainer_token, "상담 요청이 취소됐어요")
    assert row["category"] == "consultation"
    assert row["subject_id"] == member_id
    assert row["target_date"] == starts_at.astimezone(SEOUL).date().isoformat()


# ---- 담당 요청 결과 ----


def test_accepted_invite_is_its_own_kind_pointing_at_the_new_client(client, db_session):
    """수락 알림은 상담이 아니다 — 새 담당 회원을 가리키는 별도 종류다."""
    trainer, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    _accept(client, member_token, _invite(client, trainer_token, member_id))

    row = _one(client, trainer_token, "담당 요청이 수락됐어요")
    assert row["category"] == "invite_accepted"
    assert row["subject_id"] == member_id
    assert row["target_date"] is None


def test_accepted_invite_member_is_on_the_roster(client, db_session):
    """수락 알림이 가리키는 회원은 실제로 고객 목록에 있다 — 상세가 열린다."""
    _, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    _accept(client, member_token, _invite(client, trainer_token, member_id))

    row = _one(client, trainer_token, "담당 요청이 수락됐어요")
    roster = client.get("/v1/trainer/clients", headers=_auth(trainer_token)).json()
    assert row["subject_id"] in {item["id"] for item in roster}


def test_rejected_invite_is_its_own_kind(client, db_session):
    """거절 알림도 상담이 아니다. 담당이 아니라 고객 목록에는 없다."""
    _, trainer_token = _trainer(client, db_session)
    member_id, member_token = _member(client)
    _reject(client, member_token, _invite(client, trainer_token, member_id))

    row = _one(client, trainer_token, "담당 요청이 거절됐어요")
    assert row["category"] == "invite_rejected"
    assert row["subject_id"] == member_id
    assert row["target_date"] is None

    roster = client.get("/v1/trainer/clients", headers=_auth(trainer_token)).json()
    assert member_id not in {item["id"] for item in roster}


def test_invite_results_ignore_the_message_setting(client, db_session):
    """메시지 알림을 꺼도 담당 요청 결과는 온다 — 상담 요청 스위치를 따른다(#2420)."""
    _, trainer_token = _trainer(client, db_session)
    off = client.put(
        "/v1/trainer/me/settings",
        json={"notify_new_message": False},
        headers=_auth(trainer_token),
    )
    assert off.status_code == 200, off.text

    accepted_id, accepted_token = _member(client)
    rejected_id, rejected_token = _member(client)
    _accept(client, accepted_token, _invite(client, trainer_token, accepted_id))
    _reject(client, rejected_token, _invite(client, trainer_token, rejected_id))

    categories = {row["category"] for row in _inbox(client, trainer_token)}
    assert {"invite_accepted", "invite_rejected"} <= categories


def test_consultation_off_silences_invite_results(client, db_session):
    """담당 요청 수락·거절은 상담 요청 스위치를 따른다(#2420)."""
    _, trainer_token = _trainer(client, db_session)
    off = client.put(
        "/v1/trainer/me/settings",
        json={"notify_consultation": False},
        headers=_auth(trainer_token),
    )
    assert off.status_code == 200, off.text

    accepted_id, accepted_token = _member(client)
    rejected_id, rejected_token = _member(client)
    _accept(client, accepted_token, _invite(client, trainer_token, accepted_id))
    _reject(client, rejected_token, _invite(client, trainer_token, rejected_id))

    categories = {row["category"] for row in _inbox(client, trainer_token)}
    assert not categories & {"invite_accepted", "invite_rejected"}
    # 알림만 빠지고 담당 연결은 그대로 생긴다.
    roster = client.get("/v1/trainer/clients", headers=_auth(trainer_token)).json()
    assert accepted_id in {item["id"] for item in roster}


def test_no_invite_result_is_filed_as_consultation(client, db_session):
    """담당 요청만 오간 트레이너의 알림함에는 상담 알림이 없다(회귀)."""
    _, trainer_token = _trainer(client, db_session)
    accepted_id, accepted_token = _member(client)
    rejected_id, rejected_token = _member(client)
    _accept(client, accepted_token, _invite(client, trainer_token, accepted_id))
    _reject(client, rejected_token, _invite(client, trainer_token, rejected_id))

    assert all(
        row["category"] != "consultation" for row in _inbox(client, trainer_token)
    )


# ---- 응답 형태·옛 알림 ----


def test_every_inbox_row_carries_target_date(client, db_session):
    """알림함의 모든 항목에 `target_date` 키가 있다 — 없으면 null 이다."""
    trainer, trainer_token = _trainer(client, db_session)
    _insert(db_session, user_id=trainer.id, category="message")
    _insert(
        db_session,
        user_id=trainer.id,
        category="reservation",
        subject_id="someone",
        target_date="2026-10-01",
    )

    rows = _inbox(client, trainer_token)
    assert rows
    assert all("target_date" in row for row in rows)
    assert {row["target_date"] for row in rows} == {None, "2026-10-01"}


def test_old_rows_without_targets_are_still_listed(client, db_session):
    """날짜·회원이 기록되기 전의 옛 예약·상담 알림도 그대로 보인다."""
    trainer, trainer_token = _trainer(client, db_session)
    old_reservation = _insert(db_session, user_id=trainer.id, category="reservation")
    old_consultation = _insert(db_session, user_id=trainer.id, category="consultation")

    rows = {row["id"]: row for row in _inbox(client, trainer_token)}
    for notification_id in (old_reservation, old_consultation):
        assert rows[notification_id]["subject_id"] is None
        assert rows[notification_id]["target_date"] is None


def test_reading_a_targeted_notification_keeps_its_targets(client, db_session):
    """읽음 처리해도 대상 회원·날짜는 그대로 남는다."""
    trainer, trainer_token = _trainer(client, db_session)
    notification_id = _insert(
        db_session,
        user_id=trainer.id,
        category="reservation",
        subject_id="member-x",
        target_date="2026-11-02",
    )

    response = client.post(
        f"/v1/trainer/notifications/{notification_id}/read",
        headers=_auth(trainer_token),
    )
    assert response.status_code == 200, response.text
    assert response.json()["read"] is True

    row = next(
        r for r in _inbox(client, trainer_token) if r["id"] == notification_id
    )
    assert row["read"] is True
    assert row["subject_id"] == "member-x"
    assert row["target_date"] == "2026-11-02"


def test_member_token_cannot_read_the_trainer_inbox(client):
    """회원 토큰으로는 대상 정보가 실린 트레이너 알림함을 볼 수 없다."""
    _, member_token = _member(client)
    response = client.get("/v1/trainer/notifications", headers=_auth(member_token))
    assert response.status_code == 403


# ---- 서비스 단위 ----


def test_queue_for_trainer_stores_target_date(client, db_session):
    """queue_for_trainer 가 받은 날짜·회원을 그대로 저장한다."""
    trainer, _ = _trainer(client, db_session)
    row = notification_service.queue_for_trainer(
        db_session,
        trainer_id=trainer.id,
        kind=notification_service.TRAINER_RESERVATION_KIND,
        title="테스트 예약",
        subject_id="member-y",
        target_date="2026-12-24",
    )
    db_session.commit()

    assert row is not None
    db_session.expire_all()
    stored = db_session.get(Notification, row.id)
    assert stored.subject_id == "member-y"
    assert stored.target_date == "2026-12-24"


def test_queue_for_trainer_leaves_target_date_empty_by_default(client, db_session):
    """날짜를 주지 않는 종류(메시지 등)는 비워 둔다."""
    trainer, _ = _trainer(client, db_session)
    row = notification_service.queue_for_trainer(
        db_session,
        trainer_id=trainer.id,
        kind=notification_service.TRAINER_HEALTH_GOAL_KIND,
        title="테스트 목표",
        subject_id="member-z",
    )
    db_session.commit()

    assert row is not None
    db_session.expire_all()
    assert db_session.get(Notification, row.id).target_date is None


#: 종류 → 따르는 설정 칸(#2420). 트레이너 웹 설정 › 알림의 네 스위치 묶음.
_KIND_SETTING = {
    notification_service.TRAINER_MESSAGE_KIND: "notify_new_message",
    notification_service.TRAINER_CONSULTATION_KIND: "notify_consultation",
    notification_service.TRAINER_CONSULT_WITHDRAWN_KIND: "notify_consultation",
    notification_service.TRAINER_INVITE_ACCEPTED_KIND: "notify_consultation",
    notification_service.TRAINER_INVITE_REJECTED_KIND: "notify_consultation",
    notification_service.TRAINER_RESERVATION_KIND: "notify_reservation",
    notification_service.TRAINER_HEALTH_GOAL_KIND: "notify_member_updates",
    notification_service.TRAINER_MEMBER_NAME_KIND: "notify_member_updates",
    notification_service.TRAINER_MEMBER_LEFT_KIND: "notify_member_updates",
    notification_service.TRAINER_WEEKLY_FEEDBACK_KIND: "notify_member_updates",
}


def test_every_trainer_kind_has_a_switch():
    """새 트레이너 종류를 더하면 어느 스위치를 따를지 함께 정한다(#2420).

    표에 없는 종류는 항상 보내지므로, 빠뜨리면 끌 수 없는 알림이 조용히 생긴다.
    """
    kinds = {
        value
        for name, value in vars(notification_service).items()
        if name.startswith("TRAINER_") and name.endswith("_KIND")
    }
    assert kinds == set(_KIND_SETTING)
    assert notification_service._TRAINER_SETTING_COLUMN == _KIND_SETTING


@pytest.mark.parametrize(
    "column", ["notify_consultation", "notify_reservation", "notify_member_updates"]
)
def test_kind_switch_silences_only_its_own_kinds(client, db_session, column):
    """칸 하나를 끄면 그 칸을 따르는 종류만 빠지고 나머지는 그대로 온다(#2420)."""
    trainer, _ = _trainer(client, db_session)
    profile = db_session.query(TrainerProfile).filter_by(trainer_id=trainer.id).one()
    setattr(profile, column, False)
    db_session.commit()

    for kind, setting in _KIND_SETTING.items():
        row = notification_service.queue_for_trainer(
            db_session, trainer_id=trainer.id, kind=kind, title=f"테스트 {kind}"
        )
        if setting == column:
            assert row is None, kind
        else:
            assert row is not None, kind
    db_session.commit()


def test_invite_kinds_are_distinct_from_existing_kinds():
    """새 종류가 기존 트레이너 종류·회원 종류와 겹치지 않고 컬럼 폭에 들어간다."""
    new = {
        notification_service.TRAINER_INVITE_ACCEPTED_KIND,
        notification_service.TRAINER_INVITE_REJECTED_KIND,
    }
    existing = {
        notification_service.TRAINER_MESSAGE_KIND,
        notification_service.TRAINER_CONSULTATION_KIND,
        notification_service.TRAINER_RESERVATION_KIND,
        notification_service.TRAINER_HEALTH_GOAL_KIND,
        notification_service.TRAINER_MEMBER_NAME_KIND,
        notification_service.TRAINER_MEMBER_LEFT_KIND,
        notification_service.MEMBER_COACH_INVITE,
    }
    assert len(new) == 2
    assert not new & existing
    assert all(len(kind) <= 20 for kind in new)
