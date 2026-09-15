"""
포인트 사용처 라우터 — 교환 목록·교환·내 쿠폰·회원 사용 처리. (#1787)

  GET  /me/points/shop             -> { balance, has_trainer, items[] }
  POST /me/points/exchange         -> 201 { coupon, spent, balance }
  GET  /me/coupons                 -> 쿠폰 배열(사용 가능 먼저)
  POST /me/coupons/{id}/use        -> 쿠폰(회원이 사용 처리하는 쿠폰만)

트레이너의 PT 재등록 쿠폰 확인·사용 처리는 트레이너 라우터에 있다
(`/trainer/clients/{member_id}/coupons`).

읽기는 CurrentUser(데모 폴백 허용), 쓰기는 RequireMember 다 — 회원 코치 미러와
같은 규약이다.
"""
from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
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

    없는 항목은 404, 규칙에 막히면(잔액 부족·담당 트레이너 없음·사용하지 않은
    같은 종류 쿠폰 보유) 409 다.
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
        points_coupon_service.ActiveCouponExists,
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
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> CouponOut:
    """회원이 스스로 사용 완료를 누른다(건강식·보충제 쿠폰). 되돌리기는 없다.

    이미 사용했으면 같은 응답이다. 만료·취소는 409, 트레이너가 처리하는 PT 재등록
    쿠폰도 409 다.
    """
    try:
        return points_coupon_service.use_by_member(db, member.id, coupon_id)
    except points_coupon_service.CouponNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except (
        points_coupon_service.WrongRedeemer,
        points_coupon_service.CouponNotUsable,
    ) as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
