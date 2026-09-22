"""분석용 식판 — 식단 사진을 꾸준히 남긴 회원에게 주는 달성 보상. (#2150)

식단 사진 분석은 그릇이 제각각이면 양을 가늠할 기준이 없어 정확도가 떨어진다. 칸
크기와 용량을 정해 둔 규격 식판을, 사진 기록을 가장 자주 남기는 — 그래서 분석
결과를 가장 자주 보는 — 회원에게 무료로 준다.

**포인트 교환이 아니라 달성 보상이다.** 포인트는 운동 기록으로도 쌓이므로 포인트로
주면 식단 사진을 남기지 않는 회원도 받는다. 조건은 사진 기록 하나로만 본다.

규칙:

- **조건** 최근 [WINDOW_DAYS]일(KST, 오늘 포함) 중 식단 사진을 남긴 날이
  [REQUIRED_DAYS]일 이상이고, 담당 트레이너가 연결돼 있다.
  - 사진 분석으로 저장한 끼니(`diet_entries.engine` 이 있는 행)만 센다. 손으로 적은
    끼니는 세지 않는다 — 식판이 돕는 것이 사진 분석이다.
  - 하루에 여러 끼를 찍어도 하루다. 하루에 몰아 찍어서는 채울 수 없다.
  - 연속 기록 보호권(#1788)으로 이어 붙인 날은 식단 행이 없으므로 저절로 빠진다.
- **받기** 회원이 식판 카드에서 `받기` 를 누르면 0P 쿠폰(`points_coupons`, 항목
  `diet_tray`)이 생긴다. 담당 트레이너와 그 헬스장이 쿠폰에 남고, 그 헬스장에서
  받는다. 쿠폰 목록·상세·`사용 완료`(직원 확인)는 다른 쿠폰과 같다
  (`points_coupon_service`). 포인트 내역에는 남지 않는다.
- **기한이 없다**(`points_coupon_service.NO_EXPIRY`). 식판이 헬스장에 언제 닿을지는
  우리 사정이라, 그 때문에 회원의 쿠폰이 만료되면 안 된다. 헛걸음은 회원이 가기 전에
  담당 트레이너에게 채팅으로 준비됐는지 물어 막는다 — 트레이너 웹에 알림이 없어
  "준비 완료" 를 알릴 길이 아직 없다.
- **1인 1회** 사용 완료(`used`)된 식판 쿠폰이 있으면 다시 받지 않는다. 담당 해제로
  취소된 쿠폰은 식판을 받은 것이 아니므로, 새 담당이 생기고 조건을 채우고 있으면
  다시 받는다.
- **담당이 끊기면** 받지 않은 식판 쿠폰을 취소한다(`cancel_renewal_coupons`).
- 받기는 잔액 행을 잠근 채 조건을 다시 확인한다 — 같은 회원의 받기가 겹쳐도 한
  장이다. 사용 가능한 쿠폰 한 장은 partial unique index 가 마지막 방어선이다.
"""
from __future__ import annotations

import uuid
from datetime import date, timedelta

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import DietEntry, PointsCoupon
from app.schemas.diet_tray_api import DietTrayOut
from app.services import points_coupon_service, points_service

ITEM_ID = points_coupon_service.DIET_TRAY.id

#: 사진 기록일을 세는 구간(오늘 포함)과 필요한 날 수. 4주 중 20일 — 주 5일꼴이다.
WINDOW_DAYS = 28
REQUIRED_DAYS = 20

#: 상태 — 앱이 이 값으로 카드의 버튼을 고른다.
PROGRESS = "progress"
CLAIMABLE = "claimable"
ISSUED = "issued"
RECEIVED = "received"


class DietTrayError(Exception):
    """식판 받기 규칙 위반. 라우터가 409 로 옮긴다."""


class TrainerRequired(DietTrayError):
    """담당 트레이너가 있어야 받는다."""


class NotEligible(DietTrayError):
    """사진 기록일이 모자라다."""

    def __init__(self, shortfall: int) -> None:
        super().__init__(f"식단 사진 기록이 {shortfall}일 더 필요해요.")
        self.shortfall = shortfall


class AlreadyReceived(DietTrayError):
    """이미 식판을 받았다 — 1인 1회."""


class ActiveTrayCoupon(DietTrayError):
    """받지 않은 식판 쿠폰이 이미 있다."""


def window(today: date | None = None) -> tuple[date, date]:
    """사진 기록일을 세는 구간 — (첫날, 오늘)."""
    last = today or clock.today()
    return last - timedelta(days=WINDOW_DAYS - 1), last


def photo_days(db: Session, member_id: str, today: date | None = None) -> int:
    """구간 안에서 식단 사진을 남긴 날 수."""
    first, last = window(today)
    return db.scalar(
        select(func.count(func.distinct(DietEntry.date))).where(
            DietEntry.user_id == member_id,
            DietEntry.engine != "",
            DietEntry.date >= first.isoformat(),
            DietEntry.date <= last.isoformat(),
        )
    ) or 0


def state(db: Session, member_id: str) -> DietTrayOut:
    """식판 카드가 그릴 진행 상황과 상태. 기한이 지난 쿠폰을 만료로 내린다(커밋)."""
    points_coupon_service.expire_stale(db, member_id)
    db.commit()
    return _state_out(db, member_id)


def claim(
    db: Session, member_id: str, *, client_request_id: str | None = None
) -> DietTrayOut:
    """조건을 다시 확인하고 식판 수령 쿠폰을 발급한다. 커밋한다.

    [client_request_id] 로 이미 발급한 쿠폰이 있으면 새로 만들지 않고 지금 상태를
    돌려준다 — 응답을 못 받고 다시 누른 받기가 두 장을 만들지 않는다.
    """
    from app.services import trainer_service

    if client_request_id and _by_request(db, member_id, client_request_id):
        return _state_out(db, member_id)

    points_service.lock_balance(db, member_id)
    points_coupon_service.expire_stale(db, member_id)

    if _received(db, member_id) is not None:
        raise AlreadyReceived("식판은 이미 받았어요.")
    if _active(db, member_id) is not None:
        raise ActiveTrayCoupon("받지 않은 식판 쿠폰이 이미 있어요.")
    coach = trainer_service.build_member_coach(db, member_id)
    if coach is None:
        raise TrainerRequired("담당 트레이너가 있어야 받을 수 있어요.")
    days = photo_days(db, member_id)
    if days < REQUIRED_DAYS:
        raise NotEligible(REQUIRED_DAYS - days)

    issued_at = clock.now()
    coupon = PointsCoupon(
        id=f"cpn-{uuid.uuid4().hex[:12]}",
        user_id=member_id,
        item=ITEM_ID,
        cost=0,
        status=points_coupon_service.ISSUED,
        trainer_id=coach.trainer_id,
        trainer_name=coach.name,
        gym_name=coach.gym.name,
        client_request_id=client_request_id,
        issued_at=issued_at,
        expires_at=points_coupon_service.NO_EXPIRY,
    )
    try:
        db.add(coupon)
        db.commit()
    except IntegrityError:
        db.rollback()
        if client_request_id and _by_request(db, member_id, client_request_id):
            return _state_out(db, member_id)
        if _active(db, member_id) is not None:
            raise ActiveTrayCoupon("받지 않은 식판 쿠폰이 이미 있어요.") from None
        raise
    return _state_out(db, member_id)


# ---- 내부 ----


def _state_out(db: Session, member_id: str) -> DietTrayOut:
    from app.services import trainer_service

    has_trainer = trainer_service.get_member_trainer_id(db, member_id) is not None
    first, last = window()
    days = photo_days(db, member_id)
    received = _received(db, member_id)
    active = _active(db, member_id) if received is None else None
    if received is not None:
        status = RECEIVED
    elif active is not None:
        status = ISSUED
    elif has_trainer and days >= REQUIRED_DAYS:
        status = CLAIMABLE
    else:
        status = PROGRESS
    row = received or active
    return DietTrayOut(
        status=status,
        photo_days=days,
        required_days=REQUIRED_DAYS,
        window_days=WINDOW_DAYS,
        window_from=first.isoformat(),
        window_to=last.isoformat(),
        has_trainer=has_trainer,
        coupon=points_coupon_service.coupon_out(row) if row is not None else None,
    )


def _received(db: Session, member_id: str) -> PointsCoupon | None:
    return db.scalar(
        select(PointsCoupon)
        .where(
            PointsCoupon.user_id == member_id,
            PointsCoupon.item == ITEM_ID,
            PointsCoupon.status == points_coupon_service.USED,
        )
        .limit(1)
    )


def _active(db: Session, member_id: str) -> PointsCoupon | None:
    return db.scalar(
        select(PointsCoupon).where(
            PointsCoupon.user_id == member_id,
            PointsCoupon.item == ITEM_ID,
            PointsCoupon.status == points_coupon_service.ISSUED,
            PointsCoupon.expires_at > clock.now(),
        )
    )


def _by_request(db: Session, member_id: str, client_request_id: str) -> bool:
    return (
        db.scalar(
            select(PointsCoupon.id).where(
                PointsCoupon.user_id == member_id,
                PointsCoupon.item == ITEM_ID,
                PointsCoupon.client_request_id == client_request_id,
            )
        )
        is not None
    )
