"""
포인트 사용처 라우터 — 교환 목록·교환·내 쿠폰·사용 처리. (#1787)

  GET  /me/points/shop             -> { balance, has_trainer, items[] }
  POST /me/points/exchange         -> 201 { coupon, spent, balance }
  GET  /me/coupons                 -> 쿠폰 배열(사용 가능 먼저)
  POST /me/coupons/{id}/use        -> 쿠폰(회원 휴대폰에서 사용 완료)

모든 쿠폰은 헬스장이 현장에서 주는 혜택이고 회원 휴대폰에서 사용 처리한다. 직원
(PT 재등록은 트레이너·헬스장 직원)이 확인한 뒤 회원 화면의 `사용 완료` 를 누른다 —
트레이너웹 처리 경로는 없다.

읽기는 CurrentUser(데모 폴백 허용), 쓰기는 RequireMember 다 — 회원 코치 미러와
같은 규약이다.
"""
from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser, RequireMember
from app.db.session import get_db
from app.schemas.points_api import (
    CouponOut,
    ExchangeOut,
    ExchangeRequest,
    PointsShopOut,
)
from app.services import points_coupon_service, points_service
from app.services.audit import client_ip, record as record_audit

router = APIRouter(tags=["points"])


@router.get("/me/points/shop", response_model=PointsShopOut)
def points_shop(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> PointsShopOut:
    """교환 항목과 항목별 교환 가능 여부. 막힌 이유와 모자란 포인트를 함께 준다."""
    return points_coupon_service.build_shop(db, current_user.id)


@router.post("/me/points/exchange", response_model=ExchangeOut, status_code=201)
def exchange_points(
    payload: ExchangeRequest,
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> ExchangeOut:
    """포인트를 써서 쿠폰을 발급한다. 내역에는 `spend` 로 남는다.

    없는 항목은 404, 규칙에 막히면(담당 트레이너 없음·연결한 헬스장 없음·사용하지
    않은 같은 종류 쿠폰 보유·이번 달 교환·잔액 부족) 409 다.
    """
    try:
        return points_coupon_service.exchange(
            db,
            member.id,
            payload.item,
            client_request_id=payload.client_request_id,
        )
    except points_coupon_service.UnknownItem as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except points_service.InsufficientPoints as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except (
        points_coupon_service.TrainerRequired,
        points_coupon_service.GymRequired,
        points_coupon_service.ActiveCouponExists,
        points_coupon_service.MonthlyLimitReached,
    ) as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.get("/me/coupons", response_model=list[CouponOut])
def my_coupons(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> list[CouponOut]:
    """내 쿠폰. 읽을 때 만료를 반영하고 만료 3일 전 알림을 만든다."""
    return points_coupon_service.list_coupons(db, current_user.id)


@router.post("/me/coupons/{coupon_id}/use", response_model=CouponOut)
def use_my_coupon(
    coupon_id: str,
    request: Request,
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> CouponOut:
    """회원 휴대폰에서 `사용 완료` 를 누른다. 되돌리기는 없다.

    조건부 UPDATE 한 번이라 더블 탭·재전송은 한 번만 처리되고, 이미 사용된 쿠폰에는
    같은 응답(200)을 준다. 만료·취소는 409.

    모든 쿠폰이 헬스장에서 직원이 확인하고 주는 혜택이라 처음 처리한 요청에 감사
    로그(`points.coupon_redeem`)를 남긴다. 회원 휴대폰에서 누른 일이라 알림은 만들지
    않는다.
    """
    try:
        out, newly = points_coupon_service.use_by_member(db, member.id, coupon_id)
    except points_coupon_service.CouponNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except points_coupon_service.CouponNotUsable as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    if newly:
        record_audit(
            db,
            event="points.coupon_redeem",
            user_id=member.id,
            ip=client_ip(request),
            detail=f"coupon={coupon_id} item={out.item}",
        )
    return out
