"""헬스장 혜택을 닫은 서버에 남은 혜택 쿠폰을 취소하고 포인트를 돌려준다. (#2822)

PT 재등록 할인·개인 락커·분석용 식판 쿠폰은 헬스장이 현장에서 주는 혜택이다. 제휴
헬스장이 없는 동안 실서비스는 이 혜택을 닫는다(`GYM_BENEFITS_ENABLED=false`). 닫기
전에 이미 발급된 쿠폰은 회원이 들고 가도 받을 곳이 없으므로, 이 스크립트가 취소하고
교환에 쓴 포인트를 돌려준다.

- 취소·반환은 담당·헬스장 해제 때와 같은 경로다
  (`points_coupon_service.cancel_gym_benefit_coupons`). 포인트 내역에 `refund` 로
  남고, 회원마다 쿠폰 취소 알림(까닭 `service`)이 간다. 식판은 0P 라 돌려줄 포인트가
  없다.
- 기한이 지난 쿠폰은 돌려주지 않고 만료로 내린다(소멸 규칙). 이미 사용·취소된
  쿠폰은 건드리지 않는다.
- 두 번 돌려도 같다 — 취소된 쿠폰은 다시 고르지 않고, 반환은 내역의 source
  유일성으로 한 번뿐이다.

자동으로 돌지 않는다. 기본은 미리보기이고 `--apply` 를 줘야 취소한다. 서버가
혜택을 닫은 상태(플래그 꺼짐·데모 시드 꺼짐)가 아니면 `--apply` 를 거부한다 —
열린 서버에서 돌리면 회원이 곧바로 다시 교환할 수 있다.

    python -m scripts.cancel_gym_benefit_coupons            # 대상 건수만 본다
    python -m scripts.cancel_gym_benefit_coupons --apply    # 취소하고 돌려준다
"""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass, field

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.models import PointsCoupon
from app.services import points_coupon_service as pcs


@dataclass
class CancelPlan:
    """취소 대상. 미리보기와 실행이 같은 값을 쓴다."""

    member_ids: list[str] = field(default_factory=list)
    #: 항목 id → 사용 가능한 쿠폰 장수(기한이 지난 것 포함).
    coupons_by_item: dict[str, int] = field(default_factory=dict)
    #: 돌려줄 포인트 합(기한 전 쿠폰만).
    refund_points: int = 0


def build_plan(db: Session) -> CancelPlan:
    """아직 쓰지 않은 헬스장 혜택 쿠폰을 모은다(아무것도 바꾸지 않는다)."""
    rows = db.execute(
        select(
            PointsCoupon.user_id,
            PointsCoupon.item,
            PointsCoupon.cost,
            PointsCoupon.expires_at,
        ).where(
            PointsCoupon.item.in_(pcs.GYM_BENEFIT_IDS),
            PointsCoupon.status == pcs.ISSUED,
        )
    ).all()
    from app.core import clock

    now = clock.now()
    counts: Counter[str] = Counter()
    members: set[str] = set()
    refund = 0
    for row in rows:
        counts[row.item] += 1
        members.add(row.user_id)
        if row.expires_at > now:
            refund += row.cost
    return CancelPlan(
        member_ids=sorted(members),
        coupons_by_item=dict(sorted(counts.items())),
        refund_points=refund,
    )


def apply_plan(db: Session, plan: CancelPlan) -> int:
    """회원마다 취소하고 커밋한다. 취소한 장수를 돌려준다.

    회원 한 명씩 커밋한다 — 한 회원에서 실패해도 앞 회원의 반환은 남고, 다시 돌리면
    남은 회원만 처리된다.
    """
    cancelled = 0
    for member_id in plan.member_ids:
        try:
            cancelled += pcs.cancel_gym_benefit_coupons(db, member_id)
            db.commit()
        except Exception:
            db.rollback()
            raise
    return cancelled


def _print_plan(plan: CancelPlan) -> None:
    print(f"대상 회원: {len(plan.member_ids)}명")
    for item_id, count in plan.coupons_by_item.items():
        print(f"  {item_id}: {count}장")
    print(f"돌려줄 포인트(기한 전 쿠폰): {plan.refund_points:,}P")


def main() -> int:
    from app.db.session import SessionLocal

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="실제로 취소하고 포인트를 돌려준다. 없으면 건수만 출력한다.",
    )
    args = parser.parse_args()

    db = SessionLocal()
    try:
        plan = build_plan(db)
        _print_plan(plan)
        if not args.apply:
            print("미리보기 — 바꾸지 않았습니다. 취소하려면 --apply 를 붙입니다.")
            return 0
        if pcs.gym_benefits_enabled():
            print(
                "헬스장 혜택이 열린 서버입니다(GYM_BENEFITS_ENABLED 또는 데모 시드). "
                "닫은 뒤에 실행하십시오."
            )
            return 1
        cancelled = apply_plan(db, plan)
        print(f"쿠폰 {cancelled}장을 취소했습니다.")
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
