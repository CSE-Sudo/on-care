"""탈퇴하면 사라지는 것의 수 — 회원 탈퇴 확인창이 보여 준다. (#3006)

`DELETE /users/me` 는 되돌릴 수 없다. 기록·연결·대화 말고도 남은 포인트와 아직
쓰지 않은 쿠폰이 함께 사라지고, 잡아 둔 PT 예약과 대기 중 상담 요청이 취소된다.
확인창은 그 자리에서 "얼마를 잃는지" 를 숫자로 보여 줘야 한다.

여기서 세는 기준은 각 기능이 회원 화면에 보여 주는 기준과 같다 — 확인창의 숫자가
포인트·쿠폰·예약·상담 화면의 숫자와 다르면 회원이 어느 쪽도 믿지 못한다.

읽기만 한다. 만료된 쿠폰을 내리는 등의 정리도 하지 않는다.
"""
from __future__ import annotations

from datetime import datetime

from sqlalchemy.orm import Session

from app.schemas.user import AccountDeletionPreview
from app.services import (
    consultation_service,
    points_coupon_service,
    points_service,
    reservation_service,
)


def preview(
    db: Session, member_id: str, *, now: datetime | None = None
) -> AccountDeletionPreview:
    """[member_id] 가 지금 탈퇴하면 사라지거나 취소되는 것의 수."""
    return AccountDeletionPreview(
        points=points_service.balance(db, member_id),
        active_coupons=points_coupon_service.count_active(db, member_id),
        upcoming_reservations=reservation_service.count_upcoming_for_member(
            db, member_id, now=now
        ),
        pending_consultations=consultation_service.count_live_pending_for_member(
            db, member_id, now=now
        ),
    )
