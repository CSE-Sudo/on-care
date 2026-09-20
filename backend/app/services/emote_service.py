"""채팅 이모티콘 이용권 — 24시간 전체 사용. (#2020)

묶음별로 사지 않고 **한 번 사면 24시간 동안 전부** 쓴다. 묶음을 고르게 하면
회원이 무엇을 살지 고르는 사이에 정작 하려던 말을 놓치고, 안 산 묶음이 화면의
대부분을 차지한 채 잠겨 있게 된다.

- 값은 300P 다. 꾸준히 기록하면 하루 100~150P 라 이틀쯤 모으면 하루치가 된다.
- 이용 중에는 다시 사지 못한다. 남은 시간을 두고 또 사면 회원은 같은 하루를 두 번
  산 셈이 된다 — 그래서 사는 자리에서 남은 시간을 보여 주고 버튼을 막는다.
- 이용권이 끝나도 **이미 보낸 이모티콘은 대화에 그대로 남는다.** 지난 대화는
  기록이지 이용권의 대상이 아니다. 끝난 뒤에는 새로 보내는 것만 막힌다.
- **트레이너는 이용권 없이 보낸다.** 이용권은 회원이 포인트를 쓰는 자리이고,
  트레이너에게는 포인트라는 것이 없다.

만료는 스케줄러 없이 `expires_at` 을 그때그때 비교해 판단한다(쿠폰과 같은 방식).
"""
from __future__ import annotations

import uuid
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.data.emotes import EMOTE_IDS
from app.models.models import EmotePass
from app.schemas.emote_api import EmotePassOut, EmoteStateOut
from app.services import points_service

#: 포인트 사용처의 항목 id — MY 탭에서도 같은 값으로 산다.
ITEM_ID = "emote_pass_24h"
SOURCE_EMOTE_PASS = "emote_pass"

COST = 300
HOURS = 24


class EmoteError(Exception):
    """이모티콘 규칙 위반. 라우터가 상태코드로 옮긴다."""


class PassAlreadyActive(EmoteError):
    """이용 중인 이용권이 있다. 남은 시간이 [remaining_seconds] 다."""

    def __init__(self, remaining_seconds: int) -> None:
        super().__init__("이미 이용 중이에요.")
        self.remaining_seconds = remaining_seconds


class PassRequired(EmoteError):
    """이용권이 없거나 끝났다."""


class UnknownEmote(EmoteError):
    """우리가 모르는 이모티콘이다."""


def is_known(emote_id: str) -> bool:
    return emote_id in EMOTE_IDS


def active_pass(db: Session, member_id: str) -> EmotePass | None:
    """지금 쓸 수 있는 이용권. 없으면 None."""
    return db.scalars(
        select(EmotePass)
        .where(EmotePass.user_id == member_id, EmotePass.expires_at > clock.now())
        .order_by(EmotePass.expires_at.desc())
        .limit(1)
    ).first()


def _out(row: EmotePass | None) -> EmotePassOut | None:
    if row is None:
        return None
    remaining = int((row.expires_at - clock.now()).total_seconds())
    if remaining <= 0:
        return None
    return EmotePassOut(
        expires_at=row.expires_at.isoformat(), remaining_seconds=remaining
    )


def state(db: Session, member_id: str) -> EmoteStateOut:
    """이용권 상태와 값 — 고르는 창이 이것 하나로 그려진다."""
    return EmoteStateOut(
        pass_=_out(active_pass(db, member_id)),
        cost=COST,
        hours=HOURS,
        balance=points_service.balance(db, member_id),
    )


def require_pass(db: Session, member_id: str) -> None:
    """회원이 이모티콘을 보낼 수 있는지 본다. 없으면 [PassRequired]."""
    if active_pass(db, member_id) is None:
        raise PassRequired("이모티콘 이용권이 필요해요.")


def buy(
    db: Session, member_id: str, *, client_request_id: str | None = None
) -> EmoteStateOut:
    """포인트를 써서 24시간 이용권을 산다. 커밋한다.

    [client_request_id] 가 같은 재시도는 두 번 사지 않는다. 이용 중이면
    [PassAlreadyActive], 잔액이 모자라면 [points_service.InsufficientPoints] 다.
    """
    if client_request_id:
        existing = db.scalars(
            select(EmotePass).where(
                EmotePass.user_id == member_id,
                EmotePass.client_request_id == client_request_id,
            )
        ).first()
        if existing is not None:
            return state(db, member_id)

    points_service.lock_balance(db, member_id)
    current_pass = active_pass(db, member_id)
    if current_pass is not None:
        remaining = int((current_pass.expires_at - clock.now()).total_seconds())
        db.rollback()
        raise PassAlreadyActive(max(remaining, 0))
    current = points_service.balance(db, member_id)
    if current < COST:
        db.rollback()
        raise points_service.InsufficientPoints(COST - current)

    now = clock.now()
    row = EmotePass(
        id=f"emp-{uuid.uuid4().hex[:12]}",
        user_id=member_id,
        cost=COST,
        expires_at=now + timedelta(hours=HOURS),
        client_request_id=client_request_id,
    )
    try:
        db.add(row)
        db.flush()
        points_service.spend(
            db,
            member_id,
            reason=ITEM_ID,
            source_type=SOURCE_EMOTE_PASS,
            source_id=row.id,
            cost=COST,
        )
        db.commit()
    except IntegrityError:
        db.rollback()
        if client_request_id:
            return state(db, member_id)
        raise
    return state(db, member_id)
