"""회원 탈퇴로 사라지는 대기 상담 요청을 트레이너에게 알린다. (#1632) DB 필요.

회원 행을 지우면 상담 요청은 `ondelete=CASCADE` 로 함께 사라진다. 알림이 없으면
트레이너 인박스와 배지에서 요청이 이유 없이 빠진다. 여기서 보는 것:

  * 서비스 — 대기 요청을 받은 트레이너마다 한 건씩, 요청 당시 이름·희망 날짜를
    담아 남긴다. 처리된 요청·만료 시각이 지난 요청·받는 사람 없는 옛 요청은
    알리지 않는다. 담당 트레이너는 탈퇴 알림(#2174)이 따로 가므로 빠진다.
  * API — `DELETE /users/me` 뒤 트레이너 알림함에 남고, 영어 로케일에서는 영어로
    조립된다. 떠난 회원의 상세로 가는 `subject_id` 를 남기지 않는다.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest

from app.core.security import hash_password
from app.models.models import (
    ConsultationRequest,
    MemberGym,
    MemberPairingCode,
    Notification,
    Place,
    TrainerClient,
    TrainerClientInvite,
    TrainerProfile,
    TrainerReservationSlot,
    User,
)
from app.services import consultation_service, notification_service
from app.services import notification_templates as nt

EMAIL_PREFIX = "consult-withdraw-"
PLACE_PREFIX = "consult-withdraw-place-"
SLOT_PREFIX = "consult-withdraw-slot-"
PASSWORD = "withdraw-pw-1234"
KIND = notification_service.TRAINER_CONSULT_WITHDRAWN_KIND
EN = {"Accept-Language": "en"}


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
        db_session.query(ConsultationRequest).filter(
            (ConsultationRequest.member_id.in_(user_ids))
            | (ConsultationRequest.trainer_id.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(MemberPairingCode).filter(
            MemberPairingCode.member_id.in_(user_ids)
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
    db_session.query(TrainerReservationSlot).filter(
        TrainerReservationSlot.id.like(f"{SLOT_PREFIX}%")
    ).delete(synchronize_session=False)
    if user_ids:
        db_session.query(User).filter(User.id.in_(user_ids)).delete(
            synchronize_session=False
        )
    db_session.query(Place).filter(Place.id.like(f"{PLACE_PREFIX}%")).delete(
        synchronize_session=False
    )
    db_session.commit()


# --------------------------------------------------------------------------
# 준비
# --------------------------------------------------------------------------


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _register_member(client, name: str) -> tuple[str, str]:
    """API 로 가입한 회원. (id, token)"""
    email = f"{EMAIL_PREFIX}member-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": name},
    )
    assert response.status_code == 201, response.text
    return response.json()["id"], _login(client, email)


def _member_row(db_session, name: str = "탈퇴예정") -> User:
    """DB 에 바로 만든 회원 — 서비스만 부르는 테스트용."""
    suffix = uuid4().hex[:10]
    member = User(
        id=f"consult-withdraw-member-{suffix}",
        email=f"{EMAIL_PREFIX}m-{suffix}@oncare.com",
        name=name,
        role="member",
        is_active=True,
    )
    db_session.add(member)
    db_session.commit()
    return member


def _trainer(db_session, name: str = "탈퇴 테스트 트레이너") -> User:
    suffix = uuid4().hex[:10]
    place = Place(
        id=f"{PLACE_PREFIX}{suffix}",
        name="탈퇴 테스트 헬스장",
        category="fitness",
        address="서울",
    )
    db_session.add(place)
    trainer = User(
        id=f"consult-withdraw-trainer-{suffix}",
        email=f"{EMAIL_PREFIX}trainer-{suffix}@oncare.com",
        name=name,
        hashed_password=hash_password(PASSWORD),
        role="trainer",
        is_active=True,
    )
    db_session.add(trainer)
    db_session.flush()
    db_session.add(TrainerProfile(trainer_id=trainer.id, gym_id=place.id))
    db_session.commit()
    return trainer


def _slot(db_session, trainer_id: str, *, hours_ahead: float = 48) -> TrainerReservationSlot:
    slot = TrainerReservationSlot(
        id=f"{SLOT_PREFIX}{uuid4().hex[:10]}",
        trainer_id=trainer_id,
        starts_at=datetime.now(timezone.utc) + timedelta(hours=hours_ahead),
        duration_minutes=30,
        capacity=1,
        remaining=1,
        session_type="1:1 PT",
    )
    db_session.add(slot)
    db_session.commit()
    return slot


def _request_row(
    db_session,
    member: User,
    trainer: User | None,
    *,
    status: str = "pending",
    preferred_date: str = "2026-10-01",
    created_ago: timedelta = timedelta(hours=1),
    slot_id: str | None = None,
) -> ConsultationRequest:
    """상담 요청 행을 바로 만든다. 기본은 한 시간 전에 낸 대기 요청."""
    row = ConsultationRequest(
        id=f"consult-withdraw-{uuid4().hex[:12]}",
        member_id=member.id,
        target_type="trainer",
        trainer_id=trainer.id if trainer is not None else None,
        exercise_goal="fitness",
        health_purpose_type="general",
        slot_id=slot_id,
        preferred_date=preferred_date,
        preferred_time_slot="09:00",
        status=status,
        created_at=datetime.now(timezone.utc) - created_ago,
    )
    db_session.add(row)
    db_session.commit()
    return row


def _coach(db_session, member: User, trainer: User) -> None:
    db_session.add(
        TrainerClient(
            id=f"consult-withdraw-link-{uuid4().hex[:10]}",
            trainer_id=trainer.id,
            member_id=member.id,
            active=True,
        )
    )
    db_session.commit()


def _withdrawn_rows(db_session, trainer_id: str) -> list[Notification]:
    db_session.expire_all()
    return (
        db_session.query(Notification)
        .filter(Notification.user_id == trainer_id, Notification.category == KIND)
        .all()
    )


def _notify(db_session, member: User, **kwargs) -> int:
    sent = consultation_service.notify_trainers_of_account_deletion(
        db_session, member, **kwargs
    )
    db_session.commit()
    return sent


# --------------------------------------------------------------------------
# 서비스
# --------------------------------------------------------------------------


def test_every_trainer_with_a_pending_request_gets_one_notice(db_session):
    """대기 요청을 받은 트레이너마다 한 건씩, 그 요청의 희망 날짜로 남는다."""
    member = _member_row(db_session, name="지수")
    first, second = _trainer(db_session), _trainer(db_session)
    _request_row(db_session, member, first, preferred_date="2026-10-01")
    _request_row(db_session, member, second, preferred_date="2026-10-03")

    assert _notify(db_session, member) == 2

    for trainer, day in ((first, "2026-10-01"), (second, "2026-10-03")):
        rows = _withdrawn_rows(db_session, trainer.id)
        assert len(rows) == 1
        row = rows[0]
        assert row.template == nt.TRAINER_CONSULT_WITHDRAWN
        assert row.template_args == {"member_name": "지수", "preferred_date": day}
        assert row.title == "회원 탈퇴로 상담 요청이 취소됐어요"
        assert row.body == f"지수 회원 · {day}"
        assert row.target_date == day
        assert row.read is False


def test_notice_never_points_at_the_departed_member(db_session):
    """떠난 회원의 상세는 열 수 없다 — `subject_id` 를 남기지 않는다."""
    member = _member_row(db_session)
    trainer = _trainer(db_session)
    _request_row(db_session, member, trainer)

    _notify(db_session, member)

    (row,) = _withdrawn_rows(db_session, trainer.id)
    assert row.subject_id is None


@pytest.mark.parametrize("status", ["accepted", "rejected", "cancelled", "expired"])
def test_decided_requests_are_not_announced(db_session, status):
    """이미 처리된 요청은 트레이너가 결말을 안다 — 알리지 않는다."""
    member = _member_row(db_session)
    trainer = _trainer(db_session)
    _request_row(db_session, member, trainer, status=status)

    assert _notify(db_session, member) == 0
    assert _withdrawn_rows(db_session, trainer.id) == []


def test_only_the_pending_trainer_hears_when_requests_are_mixed(db_session):
    """처리된 요청을 받은 트레이너는 빠지고 대기 요청을 받은 트레이너만 남는다."""
    member = _member_row(db_session)
    waiting, decided = _trainer(db_session), _trainer(db_session)
    _request_row(db_session, member, waiting)
    _request_row(db_session, member, decided, status="rejected")

    assert _notify(db_session, member) == 1
    assert len(_withdrawn_rows(db_session, waiting.id)) == 1
    assert _withdrawn_rows(db_session, decided.id) == []


def test_current_coach_is_left_to_the_departure_notice(db_session):
    """담당 트레이너에게는 탈퇴 알림이 따로 간다 — 같은 사람에게 두 번 알리지 않는다."""
    member = _member_row(db_session)
    coach, other = _trainer(db_session), _trainer(db_session)
    _coach(db_session, member, coach)
    _request_row(db_session, member, coach)
    _request_row(db_session, member, other)

    assert _notify(db_session, member) == 1
    assert _withdrawn_rows(db_session, coach.id) == []
    assert len(_withdrawn_rows(db_session, other.id)) == 1


def test_an_inactive_link_does_not_count_as_the_coach(db_session):
    """해제된(비활성) 링크의 트레이너는 탈퇴 알림을 받지 않으므로 여기서 알린다."""
    member = _member_row(db_session)
    former = _trainer(db_session)
    db_session.add(
        TrainerClient(
            id=f"consult-withdraw-link-{uuid4().hex[:10]}",
            trainer_id=former.id,
            member_id=member.id,
            active=False,
        )
    )
    db_session.commit()
    _request_row(db_session, member, former)

    assert _notify(db_session, member) == 1
    assert len(_withdrawn_rows(db_session, former.id)) == 1


def test_requests_past_their_expiry_are_not_announced(db_session):
    """만료 시각이 지난 대기 요청은 인박스를 열면 만료로 정리된다 — 다시 꺼내지 않는다."""
    member = _member_row(db_session)
    stale_trainer, soon_trainer, fresh_trainer = (
        _trainer(db_session),
        _trainer(db_session),
        _trainer(db_session),
    )
    # 신청 후 24시간이 지났다.
    _request_row(
        db_session, member, stale_trainer, created_ago=timedelta(hours=25)
    )
    # 자리 시작 2시간 전을 넘겼다.
    soon = _slot(db_session, soon_trainer.id, hours_ahead=1)
    _request_row(db_session, member, soon_trainer, slot_id=soon.id)
    # 아직 살아 있는 요청.
    later = _slot(db_session, fresh_trainer.id, hours_ahead=48)
    _request_row(db_session, member, fresh_trainer, slot_id=later.id)

    assert _notify(db_session, member) == 1
    assert _withdrawn_rows(db_session, stale_trainer.id) == []
    assert _withdrawn_rows(db_session, soon_trainer.id) == []
    assert len(_withdrawn_rows(db_session, fresh_trainer.id)) == 1


def test_expiry_is_judged_at_the_given_moment(db_session):
    """만료 판정은 넘겨받은 시각 기준이다 — 경계 바로 앞은 알리고 경계에서는 뺀다."""
    member = _member_row(db_session)
    trainer = _trainer(db_session)
    row = _request_row(db_session, member, trainer)
    expires = row.created_at + timedelta(hours=consultation_service.CONSULT_HOLD_HOURS)

    assert _notify(db_session, member, now=expires) == 0
    assert _notify(db_session, member, now=expires - timedelta(seconds=1)) == 1


def test_legacy_request_without_a_trainer_is_skipped(db_session):
    """받을 트레이너가 없는 옛 요청(`trainer_id` 가 빈 행)에는 알림을 만들지 않는다."""
    member = _member_row(db_session)
    _request_row(db_session, member, None)

    assert _notify(db_session, member) == 0


def test_no_pending_request_means_no_notice(db_session):
    member = _member_row(db_session)
    before = db_session.query(Notification).filter(Notification.category == KIND).count()

    assert _notify(db_session, member) == 0

    db_session.expire_all()
    after = db_session.query(Notification).filter(Notification.category == KIND).count()
    assert after == before


@pytest.mark.parametrize(
    ("name", "stored_name", "body"),
    [
        ("  지수  ", "지수", "지수 회원 · 2026-10-01"),
        ("", "", "이름 없는 회원 · 2026-10-01"),
        ("   ", "", "이름 없는 회원 · 2026-10-01"),
    ],
)
def test_member_name_is_captured_before_deletion(db_session, name, stored_name, body):
    """이름은 지우기 전에 읽어 인자에 담는다. 비었으면 대신 적는 말을 쓴다."""
    member = _member_row(db_session, name=name)
    trainer = _trainer(db_session)
    _request_row(db_session, member, trainer)

    _notify(db_session, member)

    (row,) = _withdrawn_rows(db_session, trainer.id)
    assert row.template_args["member_name"] == stored_name
    assert row.body == body


def test_notice_survives_the_member_row(db_session):
    """회원 행과 요청이 지워져도 알림은 트레이너 계정에 달려 남는다."""
    member = _member_row(db_session, name="지수")
    trainer = _trainer(db_session)
    trainer_id = trainer.id
    request_id = _request_row(db_session, member, trainer).id

    consultation_service.notify_trainers_of_account_deletion(db_session, member)
    db_session.delete(member)
    db_session.commit()

    db_session.expunge_all()
    assert db_session.get(ConsultationRequest, request_id) is None
    (row,) = _withdrawn_rows(db_session, trainer_id)
    assert row.template_args["member_name"] == "지수"


def test_does_not_commit_on_its_own(db_session):
    """탈퇴와 같은 트랜잭션에 얹는다 — 되돌리면 알림도 남지 않는다."""
    member = _member_row(db_session)
    trainer = _trainer(db_session)
    _request_row(db_session, member, trainer)

    consultation_service.notify_trainers_of_account_deletion(db_session, member)
    db_session.rollback()

    assert _withdrawn_rows(db_session, trainer.id) == []


def test_withdrawn_kind_is_distinct_and_fits_the_column():
    """새 종류가 기존 트레이너 종류와 겹치지 않고 `category` 폭에 들어간다."""
    existing = {
        notification_service.TRAINER_MESSAGE_KIND,
        notification_service.TRAINER_CONSULTATION_KIND,
        notification_service.TRAINER_RESERVATION_KIND,
        notification_service.TRAINER_HEALTH_GOAL_KIND,
        notification_service.TRAINER_MEMBER_NAME_KIND,
        notification_service.TRAINER_MEMBER_LEFT_KIND,
        notification_service.TRAINER_INVITE_ACCEPTED_KIND,
        notification_service.TRAINER_INVITE_REJECTED_KIND,
    }
    assert KIND not in existing
    assert len(KIND) <= 20


# --------------------------------------------------------------------------
# API — DELETE /users/me
# --------------------------------------------------------------------------


def _trainer_token(client, trainer: User) -> str:
    return _login(client, trainer.email)


def _apply(client, db_session, member_token: str, trainer: User) -> dict:
    slot = _slot(db_session, trainer.id)
    response = client.post(
        "/v1/consultations",
        headers=_auth(member_token),
        json={
            "trainer_id": trainer.id,
            "exercise_goal": "fitness",
            "health_purpose_type": "general",
            "slot_id": slot.id,
            "message": "상담 받고 싶어요",
            "data_sharing_consent": True,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def _inbox(client, token: str, headers: dict | None = None) -> list[dict]:
    response = client.get(
        "/v1/trainer/notifications", headers={**_auth(token), **(headers or {})}
    )
    assert response.status_code == 200, response.text
    return response.json()


def _withdraw(client, member_token: str) -> None:
    response = client.delete("/v1/users/me", headers=_auth(member_token))
    assert response.status_code == 200, response.text


def test_withdrawal_tells_each_requested_trainer(client, db_session):
    """탈퇴하면 대기 요청을 받은 트레이너들의 알림함에 남고 요청은 사라진다."""
    member_id, member_token = _register_member(client, name="탈퇴상담")
    first, second = _trainer(db_session), _trainer(db_session)
    created = [
        _apply(client, db_session, member_token, first),
        _apply(client, db_session, member_token, second),
    ]

    _withdraw(client, member_token)

    db_session.expire_all()
    assert db_session.get(User, member_id) is None
    for item in created:
        assert db_session.get(ConsultationRequest, item["id"]) is None
    for trainer, item in zip((first, second), created):
        rows = [
            row
            for row in _inbox(client, _trainer_token(client, trainer))
            if row["category"] == KIND
        ]
        assert len(rows) == 1
        row = rows[0]
        assert row["title"] == "회원 탈퇴로 상담 요청이 취소됐어요"
        assert row["body"] == f"탈퇴상담 회원 · {item['preferred_date']}"
        assert row["template"] == nt.TRAINER_CONSULT_WITHDRAWN
        assert row["args"] == {
            "member_name": "탈퇴상담",
            "preferred_date": item["preferred_date"],
        }
        assert row["target_date"] == item["preferred_date"]
        assert row.get("subject_id") in (None, "")
        assert row["read"] is False


def test_withdrawal_notice_is_english_for_an_english_trainer(client, db_session):
    """영어 로케일은 같은 알림을 영어로 조립해 준다."""
    _, member_token = _register_member(client, name="Alex")
    trainer = _trainer(db_session)
    item = _apply(client, db_session, member_token, trainer)

    _withdraw(client, member_token)

    rows = [
        row
        for row in _inbox(client, _trainer_token(client, trainer), EN)
        if row["category"] == KIND
    ]
    assert len(rows) == 1
    assert rows[0]["title"] == "Consultation request cancelled: member account deleted"
    assert rows[0]["body"] == f"Alex · {item['preferred_date']}"


def test_withdrawal_clears_the_pending_badge_with_a_reason(client, db_session):
    """배지에서 요청이 빠지는 대신 미읽음 알림이 하나 는다."""
    _, member_token = _register_member(client, name="배지회원")
    trainer = _trainer(db_session)
    _apply(client, db_session, member_token, trainer)
    token = _trainer_token(client, trainer)
    headers = _auth(token)

    before = client.get("/v1/trainer/consultations/pending-count", headers=headers)
    assert before.status_code == 200, before.text
    assert before.json()["count"] == 1

    _withdraw(client, member_token)

    after = client.get("/v1/trainer/consultations/pending-count", headers=headers)
    assert after.status_code == 200, after.text
    assert after.json()["count"] == 0
    assert [row["category"] for row in _inbox(client, token)].count(KIND) == 1


def test_rejected_request_leaves_no_withdrawal_notice(client, db_session):
    """트레이너가 이미 거절한 요청은 탈퇴해도 다시 알리지 않는다."""
    _, member_token = _register_member(client, name="거절회원")
    trainer = _trainer(db_session)
    item = _apply(client, db_session, member_token, trainer)
    token = _trainer_token(client, trainer)
    rejected = client.post(
        f"/v1/trainer/consultations/{item['id']}/reject",
        headers=_auth(token),
        json={"note": None},
    )
    assert rejected.status_code == 200, rejected.text

    _withdraw(client, member_token)

    assert [row for row in _inbox(client, token) if row["category"] == KIND] == []


def test_cancelled_request_is_announced_only_once(client, db_session):
    """회원이 먼저 취소한 요청은 취소 알림(#1625)만 남고 탈퇴 알림은 없다."""
    _, member_token = _register_member(client, name="취소회원")
    trainer = _trainer(db_session)
    item = _apply(client, db_session, member_token, trainer)
    cancelled = client.delete(
        f"/v1/consultations/{item['id']}", headers=_auth(member_token)
    )
    assert cancelled.status_code == 200, cancelled.text

    _withdraw(client, member_token)

    templates = [row["template"] for row in _inbox(client, _trainer_token(client, trainer))]
    assert templates.count(nt.TRAINER_CONSULT_CANCELLED) == 1
    assert nt.TRAINER_CONSULT_WITHDRAWN not in templates


def test_coach_with_a_pending_request_hears_only_the_departure(client, db_session):
    """담당 트레이너에게 대기 요청이 있어도 탈퇴 알림(#2174) 한 건뿐이다."""
    _, member_token = _register_member(client, name="담당회원")
    coach = _trainer(db_session)
    _apply(client, db_session, member_token, coach)
    coach_token = _trainer_token(client, coach)
    issued = client.post("/v1/users/me/pairing-code", headers=_auth(member_token))
    assert issued.status_code == 200, issued.text
    redeemed = client.post(
        "/v1/trainer/pairing-code",
        json={"code": issued.json()["code"]},
        headers=_auth(coach_token),
    )
    assert redeemed.status_code == 200, redeemed.text

    _withdraw(client, member_token)

    categories = [row["category"] for row in _inbox(client, coach_token)]
    assert categories.count(notification_service.TRAINER_MEMBER_LEFT_KIND) == 1
    assert KIND not in categories


def test_member_without_requests_leaves_no_withdrawal_notice(client, db_session):
    _, member_token = _register_member(client, name="요청없음")
    before = db_session.query(Notification).filter(Notification.category == KIND).count()

    _withdraw(client, member_token)

    db_session.expire_all()
    after = db_session.query(Notification).filter(Notification.category == KIND).count()
    assert after == before
