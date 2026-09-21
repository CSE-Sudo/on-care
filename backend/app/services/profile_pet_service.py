"""MY 프로필 펫 이모지 — 포인트로 여는 기간제 꾸밈. (#2021)

MY 탭 프로필 카드의 이름 옆에 강아지나 고양이 하나를 단다. 기능에는 영향이 없다.

- 값은 200P, 기간은 산 때부터 7일이다. 꾸준히 기록하면 이틀이 안 돼 모이는 값이고,
  기간이 있어야 다시 모을 이유가 생긴다.
- **달고 있는 동안에는 다시 사지 못한다.** 남은 기간을 두고 또 사면 같은 기간을 두 번
  산 셈이다. 사용처 카드는 막히고 남은 기간을 보여 준다.
- 기간은 서버가 들고 있다. 만료는 스케줄러 없이 `expires_at` 을 그때그때 비교해
  판단한다(쿠폰·이모티콘 이용권과 같은 방식) — 지나면 저절로 떨어진다.
- 그림은 채팅 이모티콘(#2020)의 강아지·고양이를 앱이 그린다. 서버는 `kind` 만 안다.
"""
from __future__ import annotations

import uuid
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import ProfilePet
from app.schemas.points_api import ExchangeOut
from app.schemas.profile_pet_api import ProfilePetOut, ProfilePetStateOut
from app.services import points_service

#: 포인트 사용처의 항목 id — `points_coupon_service.CATALOG` 에 선다.
ITEM_ID = "profile_pet"
SOURCE_PROFILE_PET = "profile_pet"

COST = 200
DAYS = 7
#: 고를 수 있는 펫. 사용처의 고르는 창에 서는 순서 그대로다.
KINDS: tuple[str, ...] = ("dog", "cat")


class ProfilePetError(Exception):
    """펫 이모지 규칙 위반. 라우터가 상태코드로 옮긴다."""


class UnknownPet(ProfilePetError):
    """고를 수 있는 펫이 아니다."""


class PetAlreadyActive(ProfilePetError):
    """기간이 남은 펫을 달고 있다."""


def active_pet(db: Session, member_id: str) -> ProfilePet | None:
    """지금 달고 있는 펫. 없거나 기간이 끝났으면 None."""
    return db.scalars(
        select(ProfilePet)
        .where(ProfilePet.user_id == member_id, ProfilePet.expires_at > clock.now())
        .order_by(ProfilePet.expires_at.desc())
        .limit(1)
    ).first()


def pet_out(row: ProfilePet | None) -> ProfilePetOut | None:
    if row is None:
        return None
    remaining = int((row.expires_at - clock.now()).total_seconds())
    if remaining <= 0:
        return None
    return ProfilePetOut(
        kind=row.kind, expires_at=row.expires_at, remaining_seconds=remaining
    )


def state(db: Session, member_id: str) -> ProfilePetStateOut:
    """MY 프로필 카드가 읽는 하나 — 달고 있는 펫과 값·기간."""
    return ProfilePetStateOut(
        pet=pet_out(active_pet(db, member_id)),
        cost=COST,
        days=DAYS,
        kinds=list(KINDS),
    )


def exchange(
    db: Session,
    member_id: str,
    kind: str | None,
    *,
    client_request_id: str | None = None,
) -> ExchangeOut:
    """포인트를 써서 [kind] 펫을 7일 동안 단다. 커밋한다.

    [client_request_id] 가 같은 재시도는 두 번 사지 않는다. 고를 수 없는 펫은
    [UnknownPet], 기간이 남은 펫이 있으면 [PetAlreadyActive], 잔액이 모자라면
    [points_service.InsufficientPoints] 다.
    """
    if client_request_id and _by_request(db, member_id, client_request_id):
        return _exchange_out(db, member_id)
    if kind is None or kind not in KINDS:
        raise UnknownPet("고를 수 없는 펫이에요.")

    points_service.lock_balance(db, member_id)
    if active_pet(db, member_id) is not None:
        db.rollback()
        raise PetAlreadyActive("이미 달고 있는 펫이 있어요.")
    current = points_service.balance(db, member_id)
    if current < COST:
        db.rollback()
        raise points_service.InsufficientPoints(COST - current)

    row = ProfilePet(
        id=f"pet-{uuid.uuid4().hex[:12]}",
        user_id=member_id,
        kind=kind,
        cost=COST,
        expires_at=clock.now() + timedelta(days=DAYS),
        client_request_id=client_request_id,
    )
    try:
        db.add(row)
        db.flush()
        points_service.spend(
            db,
            member_id,
            reason=ITEM_ID,
            source_type=SOURCE_PROFILE_PET,
            source_id=row.id,
            cost=COST,
        )
        db.commit()
    except IntegrityError:
        db.rollback()
        if client_request_id and _by_request(db, member_id, client_request_id):
            return _exchange_out(db, member_id)
        raise
    return _exchange_out(db, member_id)


def _by_request(
    db: Session, member_id: str, client_request_id: str
) -> ProfilePet | None:
    return db.scalar(
        select(ProfilePet).where(
            ProfilePet.user_id == member_id,
            ProfilePet.client_request_id == client_request_id,
        )
    )


def _exchange_out(db: Session, member_id: str) -> ExchangeOut:
    return ExchangeOut(
        profile_pet=pet_out(active_pet(db, member_id)),
        spent=COST,
        balance=points_service.balance(db, member_id),
    )
