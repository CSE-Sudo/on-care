"""포인트 사용처 — 교환 목록·쿠폰 발급·사용 처리·만료·취소. (#1787)

사용처 화면의 혜택을 실제로 교환할 수 있게 한다. 헬스장·트레이너에게 부담이 적은
사용처를 골랐다.

- **PT 재등록 할인 쿠폰** — 담당 트레이너가 있는 회원만 교환한다. 5000P → 1만원
  할인, 30일. 재등록 1회에 1장이다. 헬스장에서 회원이 휴대폰으로 쿠폰 화면을 열고,
  트레이너·헬스장 직원이 확인한 뒤 **회원 휴대폰에서** `사용 완료` 를 누른다
  (직원 확인 버튼). 트레이너웹에는 처리 화면이 없다.
- **건강식·보충제 할인 쿠폰(데모)** — 샐러드 10%, 프로틴 3,000원. 각 1000P, 30일.
  쿠폰 화면을 보여 주고 회원이 스스로 사용 완료를 누른다. 재등록 쿠폰처럼 종류마다
  사용 가능한 쿠폰은 회원당 한 장이다.

규칙:

- 쓸 수 있는 마지막 날은 교환한 KST 날짜 + 30일이다. `expires_at` 은 그 다음 날
  KST 0시로, 이 시각부터 쓸 수 없다.
- **만료는 스케줄러 없이 늦게 반영한다.** 백엔드에 주기 작업이 없다. 기한이 지난
  `issued` 는 조회·교환·사용·취소 경로가 만날 때 `expired` 로 내린다. 응답도
  `expires_at` 을 직접 보고 상태를 계산하므로, 아직 내리지 못한 행도 만료로 보인다.
  만료되면 포인트는 돌려주지 않는다(소멸).
- **만료 3일 전 알림도 같은 방식이다.** 회원이 쿠폰 목록이나 알림함을 읽을 때 남은
  날이 3일 이하인 쿠폰마다 한 번 알림을 만든다(`expiry_reminded_at`). 그 사이 앱을
  열지 않은 회원은 받지 못한다 — 푸시가 없는 지금은 알림함을 열어야 보이므로 같은
  시점이다.
- **사용 처리는 조건부 UPDATE 한 번이다.** `issued` 이고 기한 전일 때만 `used` 로
  바꾸고, 바뀐 행이 없으면 현재 상태를 읽어 이미 사용됐으면 같은 응답을 준다. 더블
  탭·재전송이 두 번 처리되지 않고 오류도 보지 않는다. 되돌리기는 없다.
- **담당 연결이 끊기면** 사용 가능한 PT 재등록 쿠폰을 취소하고 교환에 쓴 포인트를
  돌려준다(내역 `refund`). 쓸 트레이너가 없는 쿠폰을 남겨 두면 포인트만 묶인다.
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta

from sqlalchemy import case, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import PointsCoupon
from app.schemas.points_api import (
    CouponOut,
    ExchangeOut,
    PointsShopOut,
    ShopItemOut,
)
from app.services import notification_service, points_service

#: 누가 사용 처리하나. 지금은 모든 쿠폰을 회원 휴대폰에서 처리한다 — PT 재등록
#: 쿠폰도 직원이 확인한 뒤 회원 화면의 버튼을 누른다.
REDEEMER_MEMBER = "member"

#: 쿠폰 상태.
ISSUED = "issued"
USED = "used"
EXPIRED = "expired"
CANCELLED = "cancelled"

#: 교환 버튼을 막는 이유 — 앱이 이 값으로 안내 문구를 고른다.
BLOCK_NO_TRAINER = "no_trainer"
BLOCK_ACTIVE_COUPON = "active_coupon"
BLOCK_INSUFFICIENT = "insufficient_points"

#: 만료 알림을 보내기 시작하는 남은 날 수.
REMIND_DAYS_BEFORE = 3

#: 회원 쿠폰 목록 상한. 쿠폰은 쌓이기만 하므로 응답 크기를 묶는다.
_LIST_LIMIT = 100


@dataclass(frozen=True)
class ShopItem:
    """사용처 화면의 교환 항목 하나. 가격·기한의 원본은 서버다."""

    id: str
    title: str
    benefit: str
    description: str
    cost: int
    valid_days: int
    redeemer: str
    requires_trainer: bool = False
    #: 사용 가능한 쿠폰을 한 장만 가질 수 있는가.
    one_active: bool = False


PT_RENEWAL = ShopItem(
    id="pt_renewal",
    title="PT 재등록 할인 쿠폰",
    benefit="PT 재등록 10,000원 할인",
    description="담당 트레이너에게 PT를 다시 등록할 때 10,000원을 할인받아요.",
    cost=5000,
    valid_days=30,
    redeemer=REDEEMER_MEMBER,
    requires_trainer=True,
    one_active=True,
)
SALAD_DISCOUNT = ShopItem(
    id="salad_discount",
    title="샐러드 10% 할인",
    benefit="샐러드 10% 할인",
    description="건강식 샐러드를 주문할 때 10% 할인받아요.",
    cost=1000,
    valid_days=30,
    redeemer=REDEEMER_MEMBER,
    one_active=True,
)
PROTEIN_DISCOUNT = ShopItem(
    id="protein_discount",
    title="프로틴 3,000원 할인",
    benefit="프로틴 3,000원 할인",
    description="프로틴 보충제를 살 때 3,000원 할인받아요.",
    cost=1000,
    valid_days=30,
    redeemer=REDEEMER_MEMBER,
    one_active=True,
)

#: 화면에 서는 순서 그대로다.
CATALOG: tuple[ShopItem, ...] = (PT_RENEWAL, SALAD_DISCOUNT, PROTEIN_DISCOUNT)
_ITEMS: dict[str, ShopItem] = {item.id: item for item in CATALOG}


class CouponError(Exception):
    """사용처·쿠폰 규칙 위반. 라우터가 상태코드로 옮긴다."""


class UnknownItem(CouponError):
    """카탈로그에 없는 항목이다."""


class TrainerRequired(CouponError):
    """담당 트레이너가 있어야 교환할 수 있다."""


class ActiveCouponExists(CouponError):
    """사용하지 않은 같은 쿠폰이 이미 있다."""


class CouponNotFound(CouponError):
    """없거나 남의 쿠폰이다."""


class CouponNotUsable(CouponError):
    """만료·취소돼 사용할 수 없다. [status] 가 그 상태다."""

    def __init__(self, status: str) -> None:
        message = "만료된 쿠폰이에요." if status == EXPIRED else "취소된 쿠폰이에요."
        super().__init__(message)
        self.status = status


def item_of(item_id: str) -> ShopItem | None:
    return _ITEMS.get(item_id)


# ---- 조회 ----


def build_shop(db: Session, member_id: str) -> PointsShopOut:
    """교환 목록과 항목별 교환 가능 여부. 아무것도 쓰지 않는다.

    가능 여부를 서버가 계산해 준다 — 앱이 담당 여부·보유 쿠폰 규칙을 따로 들고
    있으면 규칙이 바뀔 때 화면만 옛 규칙으로 남는다.
    """
    from app.services import trainer_service

    balance = points_service.balance(db, member_id)
    has_trainer = trainer_service.get_member_trainer_id(db, member_id) is not None
    now = clock.now()
    active_items = set(
        db.scalars(
            select(PointsCoupon.item).where(
                PointsCoupon.user_id == member_id,
                PointsCoupon.status == ISSUED,
                PointsCoupon.expires_at > now,
            )
        ).all()
    )
    items: list[ShopItemOut] = []
    for item in CATALOG:
        shortfall = max(item.cost - balance, 0)
        blocked: str | None = None
        if item.requires_trainer and not has_trainer:
            blocked = BLOCK_NO_TRAINER
        elif item.one_active and item.id in active_items:
            blocked = BLOCK_ACTIVE_COUPON
        elif shortfall > 0:
            blocked = BLOCK_INSUFFICIENT
        items.append(
            ShopItemOut(
                id=item.id,
                title=item.title,
                benefit=item.benefit,
                description=item.description,
                cost=item.cost,
                valid_days=item.valid_days,
                redeemer=item.redeemer,
                requires_trainer=item.requires_trainer,
                available=blocked is None,
                blocked_reason=blocked,
                shortfall=shortfall,
            )
        )
    return PointsShopOut(balance=balance, has_trainer=has_trainer, items=items)


def list_coupons(db: Session, member_id: str) -> list[CouponOut]:
    """내 쿠폰 — 사용 가능한 것 먼저, 그다음 최신순.

    읽기 전에 기한이 지난 쿠폰을 만료로 내리고, 만료가 가까운 쿠폰의 알림을 만든다.
    """
    _expire_stale(db, member_id)
    remind_expiring(db, member_id)
    db.commit()
    now = clock.now()
    rows = db.scalars(
        select(PointsCoupon)
        .where(PointsCoupon.user_id == member_id)
        .order_by(
            case((PointsCoupon.status == ISSUED, 0), else_=1),
            PointsCoupon.issued_at.desc(),
            PointsCoupon.id.desc(),
        )
        .limit(_LIST_LIMIT)
    ).all()
    return [coupon_out(row, now) for row in rows]


# ---- 교환 ----


def exchange(
    db: Session,
    member_id: str,
    item_id: str,
    *,
    client_request_id: str | None = None,
) -> ExchangeOut:
    """포인트를 써서 쿠폰 한 장을 발급한다. 커밋한다.

    [client_request_id] 로 이미 발급한 쿠폰이 있으면 새로 쓰지 않고 그 쿠폰을
    돌려준다 — 응답을 못 받고 다시 누른 교환이 포인트를 두 번 쓰지 않는다.

    잔액 행을 먼저 잠근다. 같은 회원의 교환이 동시에 들어와도 "사용 가능한 같은
    종류 쿠폰이 있나"·"잔액이 되나" 를 차례로 보게 된다. partial unique index 가
    마지막 방어선이다.
    """
    from app.services import trainer_service

    item = _ITEMS.get(item_id)
    if item is None:
        raise UnknownItem("없는 교환 항목이에요.")
    if client_request_id:
        existing = _by_request(db, member_id, client_request_id)
        if existing is not None:
            return _exchange_out(db, member_id, existing)

    points_service.lock_balance(db, member_id)
    _expire_stale(db, member_id)

    trainer_id: str | None = None
    trainer_name = ""
    gym_name = ""
    if item.requires_trainer:
        coach = trainer_service.build_member_coach(db, member_id)
        if coach is None:
            raise TrainerRequired("담당 트레이너가 있어야 교환할 수 있어요.")
        trainer_id = coach.trainer_id
        trainer_name = coach.name
        gym_name = coach.gym.name
    if item.one_active and _active_coupon(db, member_id, item.id) is not None:
        raise ActiveCouponExists("사용하지 않은 쿠폰이 이미 있어요.")
    current = points_service.balance(db, member_id)
    if current < item.cost:
        raise points_service.InsufficientPoints(item.cost - current)

    issued_at = clock.now()
    coupon = PointsCoupon(
        id=f"cpn-{uuid.uuid4().hex[:12]}",
        user_id=member_id,
        item=item.id,
        cost=item.cost,
        status=ISSUED,
        trainer_id=trainer_id,
        trainer_name=trainer_name,
        gym_name=gym_name,
        client_request_id=client_request_id,
        issued_at=issued_at,
        expires_at=_expires_at(issued_at, item.valid_days),
    )
    try:
        db.add(coupon)
        db.flush()
        points_service.spend(
            db,
            member_id,
            reason=f"coupon_{item.id}",
            source_type=points_service.SOURCE_POINTS_COUPON,
            source_id=coupon.id,
            cost=item.cost,
        )
        db.commit()
    except IntegrityError:
        db.rollback()
        if client_request_id:
            existing = _by_request(db, member_id, client_request_id)
            if existing is not None:
                return _exchange_out(db, member_id, existing)
        if item.one_active and _active_coupon(db, member_id, item.id) is not None:
            raise ActiveCouponExists("사용하지 않은 쿠폰이 이미 있어요.") from None
        raise
    db.refresh(coupon)
    return _exchange_out(db, member_id, coupon)


# ---- 사용 처리 ----


def use_by_member(
    db: Session, member_id: str, coupon_id: str
) -> tuple[CouponOut, bool]:
    """회원 휴대폰에서 `사용 완료` 를 누른다. 커밋한다.

    PT 재등록 쿠폰은 트레이너·헬스장 직원이 확인한 뒤, 건강식·보충제 쿠폰은 매장에서
    쿠폰 화면을 보여 준 뒤 회원 화면의 같은 버튼으로 처리한다. 사용 시각은 `used_at` 에
    남는다 — 처리한 사람은 늘 이 회원이라 따로 적지 않는다.

    두 번째 값은 **이번 요청이 처리했는가**다. 이미 사용된 쿠폰의 재요청은 같은
    응답에 거짓이라, 라우터는 참일 때만 감사 로그를 남긴다. 만료·취소는
    [CouponNotUsable].
    """
    row = db.scalar(
        select(PointsCoupon).where(
            PointsCoupon.id == coupon_id, PointsCoupon.user_id == member_id
        )
    )
    if row is None:
        raise CouponNotFound("쿠폰을 찾을 수 없어요.")
    newly = _claim(db, row)
    if newly:
        db.commit()
        db.refresh(row)
    return coupon_out(row), newly


# ---- 만료·알림·취소 ----


def remind_expiring(db: Session, member_id: str) -> int:
    """남은 날이 3일 이하인 쿠폰마다 한 번 만료 알림을 만든다. 커밋하지 않는다.

    쿠폰 행에 `expiry_reminded_at` 을 먼저 조건부로 채우고, 채운 요청만 알림을
    만든다 — 목록과 알림함을 동시에 열어도 알림은 한 건이다.
    """
    now = clock.now()
    boundary = datetime.combine(
        clock.today() + timedelta(days=REMIND_DAYS_BEFORE + 1),
        time.min,
        tzinfo=clock.SEOUL,
    )
    rows = db.scalars(
        select(PointsCoupon).where(
            PointsCoupon.user_id == member_id,
            PointsCoupon.status == ISSUED,
            PointsCoupon.expires_at > now,
            PointsCoupon.expires_at <= boundary,
            PointsCoupon.expiry_reminded_at.is_(None),
        )
    ).all()
    sent = 0
    for row in rows:
        claimed = db.execute(
            update(PointsCoupon)
            .where(
                PointsCoupon.id == row.id,
                PointsCoupon.expiry_reminded_at.is_(None),
            )
            .values(expiry_reminded_at=now)
            .execution_options(synchronize_session=False)
        )
        if claimed.rowcount != 1:
            continue
        item = _ITEMS.get(row.item)
        benefit = item.benefit if item is not None else row.item
        last_day = _expires_on(row)
        days = _days_left(last_day)
        when = (
            f"{benefit} 쿠폰은 오늘까지 쓸 수 있어요."
            if days == 0
            else f"{benefit} 쿠폰이 {days}일 뒤({last_day.month}월 {last_day.day}일) 만료돼요."
        )
        notification_service.queue(
            db,
            member_id=member_id,
            kind=notification_service.POINTS_COUPON,
            category=notification_service.MEMBER_BENEFITS,
            title="쿠폰이 곧 만료돼요",
            body=f"{when} 만료되면 포인트는 돌려받을 수 없어요.",
        )
        sent += 1
    return sent


def cancel_renewal_coupons(db: Session, member_id: str) -> int:
    """담당 연결이 끊긴 회원의 PT 재등록 쿠폰을 취소하고 포인트를 돌려준다.

    취소한 장수를 돌려준다. 커밋하지 않는다 — 담당 해제와 같은 트랜잭션이어야
    "연결은 끊겼는데 쿠폰은 살아 있는" 반쪽 상태가 생기지 않는다.

    이미 기한이 지난 쿠폰은 돌려주지 않고 만료로 내린다(소멸 규칙). 잔액 행을
    쿠폰보다 먼저 잠근다 — 교환과 같은 순서라 서로 기다리다 멈추지 않는다.
    """
    has_any = db.scalar(
        select(PointsCoupon.id)
        .where(
            PointsCoupon.user_id == member_id,
            PointsCoupon.item == PT_RENEWAL.id,
            PointsCoupon.status == ISSUED,
        )
        .limit(1)
    )
    if has_any is None:
        return 0
    points_service.lock_balance(db, member_id)
    rows = db.scalars(
        select(PointsCoupon)
        .where(
            PointsCoupon.user_id == member_id,
            PointsCoupon.item == PT_RENEWAL.id,
            PointsCoupon.status == ISSUED,
        )
        .with_for_update()
    ).all()
    now = clock.now()
    cancelled = 0
    for row in rows:
        if row.expires_at <= now:
            row.status = EXPIRED
            continue
        row.status = CANCELLED
        row.cancelled_at = now
        refunded = points_service.refund(
            db, member_id, points_service.SOURCE_POINTS_COUPON, row.id
        )
        notification_service.queue(
            db,
            member_id=member_id,
            kind=notification_service.POINTS_COUPON,
            category=notification_service.MEMBER_BENEFITS,
            title="재등록 쿠폰이 취소됐어요",
            body=(
                f"담당 트레이너 연결이 해제되어 {PT_RENEWAL.benefit} 쿠폰을 취소하고 "
                f"{refunded:,}P를 돌려드렸어요."
            ),
        )
        cancelled += 1
    db.flush()
    return cancelled


# ---- 응답 ----


def coupon_out(row: PointsCoupon, now: datetime | None = None) -> CouponOut:
    now = now or clock.now()
    item = _ITEMS.get(row.item)
    status = _status(row, now)
    last_day = _expires_on(row)
    return CouponOut(
        id=row.id,
        item=row.item,
        title=item.title if item is not None else row.item,
        benefit=item.benefit if item is not None else row.item,
        cost=row.cost,
        status=status,
        redeemer=item.redeemer if item is not None else REDEEMER_MEMBER,
        trainer_name=row.trainer_name or "",
        gym_name=row.gym_name or "",
        issued_at=row.issued_at,
        issued_on=clock.to_seoul(row.issued_at).date().isoformat(),
        expires_at=row.expires_at,
        expires_on=last_day.isoformat(),
        days_left=_days_left(last_day) if status == ISSUED else 0,
        used_at=row.used_at,
        cancelled_at=row.cancelled_at,
    )


# ---- 내부 ----


def _claim(db: Session, row: PointsCoupon) -> bool:
    """조건부 UPDATE 한 번으로 사용 처리한다. 이번에 바꿨으면 True.

    커밋하지 않는다. 바뀐 행이 없으면 현재 상태를 읽어, 이미 사용됐으면 False,
    만료·취소면 [CouponNotUsable] 이다.
    """
    now = clock.now()
    result = db.execute(
        update(PointsCoupon)
        .where(
            PointsCoupon.id == row.id,
            PointsCoupon.status == ISSUED,
            PointsCoupon.expires_at > now,
        )
        .values(status=USED, used_at=now)
        .execution_options(synchronize_session=False)
    )
    if result.rowcount == 1:
        return True
    db.refresh(row)
    if row.status == USED:
        return False
    if row.status == ISSUED:
        # 기한이 지났다 — 만료로 내려 두고 알린다.
        _expire_stale(db, row.user_id)
        db.commit()
        raise CouponNotUsable(EXPIRED)
    raise CouponNotUsable(row.status)


def _expire_stale(db: Session, member_id: str) -> None:
    """기한이 지난 사용 가능 쿠폰을 만료로 내린다. 커밋하지 않는다."""
    db.execute(
        update(PointsCoupon)
        .where(
            PointsCoupon.user_id == member_id,
            PointsCoupon.status == ISSUED,
            PointsCoupon.expires_at <= clock.now(),
        )
        .values(status=EXPIRED)
        .execution_options(synchronize_session=False)
    )


def _active_coupon(db: Session, member_id: str, item_id: str) -> PointsCoupon | None:
    return db.scalar(
        select(PointsCoupon).where(
            PointsCoupon.user_id == member_id,
            PointsCoupon.item == item_id,
            PointsCoupon.status == ISSUED,
            PointsCoupon.expires_at > clock.now(),
        )
    )


def _by_request(
    db: Session, member_id: str, client_request_id: str
) -> PointsCoupon | None:
    return db.scalar(
        select(PointsCoupon).where(
            PointsCoupon.user_id == member_id,
            PointsCoupon.client_request_id == client_request_id,
        )
    )


def _exchange_out(db: Session, member_id: str, row: PointsCoupon) -> ExchangeOut:
    return ExchangeOut(
        coupon=coupon_out(row),
        spent=row.cost,
        balance=points_service.balance(db, member_id),
    )


def _expires_at(issued_at: datetime, valid_days: int) -> datetime:
    """쓸 수 없게 되는 시각 — 마지막 사용일(교환일 + [valid_days]) 다음 날 KST 0시."""
    last_day = clock.to_seoul(issued_at).date() + timedelta(days=valid_days)
    return datetime.combine(last_day + timedelta(days=1), time.min, tzinfo=clock.SEOUL)


def _expires_on(row: PointsCoupon) -> date:
    """쓸 수 있는 마지막 날(KST)."""
    return clock.to_seoul(row.expires_at).date() - timedelta(days=1)


def _days_left(last_day: date) -> int:
    return max((last_day - clock.today()).days, 0)


def _status(row: PointsCoupon, now: datetime) -> str:
    """응답에 싣는 상태. 아직 만료로 내리지 못한 행도 기한이 지났으면 만료다."""
    if row.status == ISSUED and row.expires_at <= now:
        return EXPIRED
    return row.status
