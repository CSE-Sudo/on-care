"""탈퇴 미리보기 — 탈퇴하면 사라지거나 취소되는 것의 수. (#3006) DB 필요.

회원 탈퇴 확인창은 "보유 포인트 1,200P가 사라져요" 처럼 이 계정의 숫자로 말한다.
숫자는 각 기능이 회원 화면에 보여 주는 기준과 같아야 한다. 여기서 보는 것:

  * 서비스 — 포인트 잔액, 쓸 수 있는 쿠폰(사용·취소·만료·기한 지난 것 제외),
    앞으로의 예약(지난 예약·취소된 예약·트레이너가 취소한 일정 제외), 아직
    살아 있는 대기 상담 요청(처리된 것·만료 시각이 지난 것 제외). 다른 회원의
    행은 섞이지 않는다.
  * API — `GET /users/me/deletion-preview` 가 네 칸을 주고, 아무것도 바꾸지 않으며,
    트레이너 계정에는 403 이다.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest

from app.core.security import hash_password
from app.models.models import (
    ConsultationRequest,
    HealthProfile,
    PointsCoupon,
    TrainerReservation,
    TrainerReservationSlot,
    TrainerSchedule,
    User,
)
from app.services import account_deletion_preview
from app.services.trainer import _common as trainer_common_service

EMAIL_PREFIX = "deletion-preview-"
ID_PREFIX = "deletion-preview-"
PASSWORD = "preview-pw-1234"
URL = "/v1/users/me/deletion-preview"


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
            TrainerSchedule.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(ConsultationRequest).filter(
            (ConsultationRequest.member_id.in_(user_ids))
            | (ConsultationRequest.trainer_id.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(TrainerReservationSlot).filter(
            TrainerReservationSlot.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(PointsCoupon).filter(
            PointsCoupon.user_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(HealthProfile).filter(
            HealthProfile.user_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(User).filter(User.id.in_(user_ids)).delete(
            synchronize_session=False
        )
    db_session.commit()


# --------------------------------------------------------------------------
# 준비
# --------------------------------------------------------------------------


def _suffix() -> str:
    return uuid4().hex[:10]


def _user(db_session, role: str = "member") -> User:
    suffix = _suffix()
    user = User(
        id=f"{ID_PREFIX}{role}-{suffix}",
        email=f"{EMAIL_PREFIX}{role}-{suffix}@oncare.com",
        name=f"미리보기 {role}",
        hashed_password=hash_password(PASSWORD),
        role=role,
        is_active=True,
    )
    db_session.add(user)
    db_session.commit()
    return user


def _points(db_session, member: User, points: int) -> None:
    db_session.add(HealthProfile(user_id=member.id, activity_points=points))
    db_session.commit()


def _coupon(
    db_session,
    member: User,
    *,
    item: str,
    status: str = "issued",
    expires_in: timedelta = timedelta(days=30),
) -> None:
    now = datetime.now(timezone.utc)
    db_session.add(
        PointsCoupon(
            id=f"{ID_PREFIX}coupon-{_suffix()}",
            user_id=member.id,
            item=item,
            cost=500,
            status=status,
            issued_at=now - timedelta(days=1),
            expires_at=now + expires_in,
        )
    )
    db_session.commit()


def _booking(
    db_session,
    member: User,
    trainer: User,
    *,
    starts_in: timedelta = timedelta(days=2),
    status: str = "booked",
    schedule_status: str = trainer_common_service.SCHEDULE_UPCOMING,
) -> None:
    starts_at = datetime.now(timezone.utc) + starts_in
    slot = TrainerReservationSlot(
        id=f"{ID_PREFIX}slot-{_suffix()}",
        trainer_id=trainer.id,
        starts_at=starts_at,
        duration_minutes=60,
        capacity=1,
        remaining=0,
        session_type="1:1 PT",
    )
    schedule = TrainerSchedule(
        id=f"{ID_PREFIX}sched-{_suffix()}",
        trainer_id=trainer.id,
        member_id=member.id,
        date=starts_at.date().isoformat(),
        time="10:00",
        type="1:1 PT",
        duration_minutes=60,
        status=schedule_status,
    )
    db_session.add_all([slot, schedule])
    db_session.flush()
    db_session.add(
        TrainerReservation(
            id=f"{ID_PREFIX}res-{_suffix()}",
            member_id=member.id,
            slot_id=slot.id,
            schedule_id=schedule.id,
            status=status,
        )
    )
    db_session.commit()


def _consultation(
    db_session,
    member: User,
    trainer: User,
    *,
    status: str = "pending",
    created_ago: timedelta = timedelta(hours=1),
) -> None:
    db_session.add(
        ConsultationRequest(
            id=f"{ID_PREFIX}consult-{_suffix()}",
            member_id=member.id,
            target_type="trainer",
            trainer_id=trainer.id,
            exercise_goal="fitness",
            health_purpose_type="general",
            preferred_date="2026-10-10",
            preferred_time_slot="09:00",
            status=status,
            created_at=datetime.now(timezone.utc) - created_ago,
        )
    )
    db_session.commit()


def _preview(db_session, member: User):
    db_session.expire_all()
    return account_deletion_preview.preview(db_session, member.id)


def _login(client, user: User) -> dict[str, str]:
    response = client.post(
        "/v1/auth/login", data={"username": user.email, "password": PASSWORD}
    )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


# --------------------------------------------------------------------------
# 서비스
# --------------------------------------------------------------------------


def test_new_member_loses_nothing(db_session):
    """아무것도 없는 계정은 네 칸이 모두 0 이다 — 프로필 행이 없어도 된다."""
    member = _user(db_session)

    p = _preview(db_session, member)

    assert (p.points, p.active_coupons) == (0, 0)
    assert (p.upcoming_reservations, p.pending_consultations) == (0, 0)


def test_points_are_the_current_balance(db_session):
    member = _user(db_session)
    _points(db_session, member, 1240)

    assert _preview(db_session, member).points == 1240


def test_only_usable_coupons_are_counted(db_session):
    """사용·취소·만료된 쿠폰과, 기한이 지났지만 아직 내리지 못한 쿠폰은 빠진다."""
    member = _user(db_session)
    _coupon(db_session, member, item="pt_renewal")
    _coupon(db_session, member, item="locker")
    _coupon(db_session, member, item="meal_plate", status="used")
    _coupon(db_session, member, item="streak_shield", status="cancelled")
    _coupon(db_session, member, item="graph_color", status="expired")
    # 기한이 지났는데 아직 `issued` — 만료는 읽는 쪽이 늦게 반영한다.
    _coupon(
        db_session, member, item="report_pdf", expires_in=timedelta(hours=-1)
    )

    assert _preview(db_session, member).active_coupons == 2


def test_only_upcoming_live_bookings_are_counted(db_session):
    """앞으로의 예약만 — 지난 예약·취소된 예약·트레이너가 취소한 일정은 빠진다."""
    member = _user(db_session)
    trainer = _user(db_session, role="trainer")
    _booking(db_session, member, trainer, starts_in=timedelta(days=1))
    _booking(db_session, member, trainer, starts_in=timedelta(hours=3))
    _booking(db_session, member, trainer, starts_in=timedelta(days=-2))
    _booking(db_session, member, trainer, status="cancelled")
    _booking(
        db_session,
        member,
        trainer,
        schedule_status=trainer_common_service.SCHEDULE_CANCELLED,
    )

    assert _preview(db_session, member).upcoming_reservations == 2


def test_only_live_pending_consultations_are_counted(db_session):
    """처리된 요청과 만료 시각(신청 후 24시간)이 지난 대기 요청은 빠진다."""
    member = _user(db_session)
    trainer = _user(db_session, role="trainer")
    _consultation(db_session, member, trainer)
    _consultation(db_session, member, trainer, status="accepted")
    _consultation(db_session, member, trainer, status="rejected")
    # 같은 트레이너에게 대기 요청은 하나뿐이라(부분 유일 인덱스) 만료 요청은 다른 트레이너에게 둔다.
    other_trainer = _user(db_session, role="trainer")
    _consultation(db_session, member, other_trainer, created_ago=timedelta(hours=30))

    assert _preview(db_session, member).pending_consultations == 1


def test_other_members_rows_never_leak_in(db_session):
    """다른 회원의 포인트·쿠폰·예약·상담은 섞이지 않는다."""
    member = _user(db_session)
    other = _user(db_session)
    trainer = _user(db_session, role="trainer")
    _points(db_session, other, 900)
    _coupon(db_session, other, item="pt_renewal")
    _booking(db_session, other, trainer)
    _consultation(db_session, other, trainer)

    p = _preview(db_session, member)

    assert (p.points, p.active_coupons) == (0, 0)
    assert (p.upcoming_reservations, p.pending_consultations) == (0, 0)


# --------------------------------------------------------------------------
# API
# --------------------------------------------------------------------------


def test_api_returns_the_four_counts(client, db_session):
    member = _user(db_session)
    trainer = _user(db_session, role="trainer")
    _points(db_session, member, 1200)
    _coupon(db_session, member, item="pt_renewal")
    _booking(db_session, member, trainer)
    _consultation(db_session, member, trainer)

    response = client.get(URL, headers=_login(client, member))

    assert response.status_code == 200, response.text
    assert response.json() == {
        "points": 1200,
        "active_coupons": 1,
        "upcoming_reservations": 1,
        "pending_consultations": 1,
    }


def test_api_reads_without_changing_anything(client, db_session):
    """미리보기는 읽기만 한다 — 기한 지난 쿠폰도 `expired` 로 내리지 않는다."""
    member = _user(db_session)
    _coupon(db_session, member, item="pt_renewal", expires_in=timedelta(hours=-1))
    headers = _login(client, member)

    first = client.get(URL, headers=headers)
    second = client.get(URL, headers=headers)

    assert first.status_code == second.status_code == 200
    assert first.json() == second.json()
    db_session.expire_all()
    statuses = [
        row.status
        for row in db_session.query(PointsCoupon).filter(
            PointsCoupon.user_id == member.id
        )
    ]
    assert statuses == ["issued"]
    assert db_session.get(User, member.id) is not None


def test_api_is_for_members_only(client, db_session):
    trainer = _user(db_session, role="trainer")

    response = client.get(URL, headers=_login(client, trainer))

    assert response.status_code == 403


def test_api_requires_a_session(client):
    assert client.get(URL).status_code == 401
