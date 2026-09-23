"""채팅 이모티콘 — 하나씩 사서 7일 동안 쓴다. (#2153)

처음에는 24시간 이용권 하나로 모든 이모티콘을 열었다(#2020). 그런데 회원이 트레이너
채팅에서 쓰는 이모티콘은 몇 개로 정해져 있고, 24시간은 PT 주기(주 2~3회)보다 짧아
수업마다 다시 사야 했다. 그래서 **쓰고 싶은 이모티콘만 골라 사고, 산 것은 7일 동안**
쓰게 바꿨다.

- 값은 하나에 50P 다. 식단 사진 한 장 적립과 같은 값이라 "사진 한 장 = 이모티콘 한 주"
  로 읽힌다.
- 쓰고 있는 이모티콘은 다시 사지 못한다. 남은 기간을 두고 또 사면 같은 주를 두 번 산
  셈이 된다 — 사는 자리에서 남은 기간을 보여 준다.
- 기간이 끝나도 **이미 보낸 이모티콘은 대화에 그대로 남는다.** 끝난 뒤에는 새로 보내는
  것만 막힌다.
- **트레이너는 사지 않고 모두 보낸다.** 트레이너에게는 포인트라는 것이 없다.
- **담당 트레이너가 있어야 산다**(#2142). 이모티콘은 트레이너 채팅에만 있다. 이미 산
  이모티콘은 쓰던 중 담당이 끊겨도 남은 기간을 빼앗지 않는다.
- 포인트 사용처에서는 팔지 않는다. 무엇을 사는지는 고르는 자리(채팅의 이모티콘 창)에서
  봐야 알 수 있다.
- 바뀌기 전에 산 24시간 이용권(`emote_passes`)은 남은 시간 동안 모든 이모티콘을 그대로
  쓴다. 상태 응답은 그 이용권을 이모티콘마다 연 것으로 풀어 준다 — 앱은 한 모양만 본다.

만료는 스케줄러 없이 `expires_at` 을 그때그때 비교해 판단한다(쿠폰과 같은 방식).
"""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.data.emotes import EMOTE_IDS
from app.models.models import EmotePass, EmoteUnlock
from app.schemas.emote_api import EmoteStateOut, EmoteUnlockOut
from app.services import points_service

#: 포인트 원장의 사유 코드. 지난 24시간 이용권은 `emote_pass_24h` 로 남아 있다.
REASON_EMOTE_UNLOCK = "emote_unlock"
SOURCE_EMOTE_UNLOCK = "emote_unlock"

COST = 50
DAYS = 7


class EmoteError(Exception):
    """이모티콘 규칙 위반. 라우터가 상태코드로 옮긴다."""


class AlreadyUnlocked(EmoteError):
    """그 이모티콘을 이미 쓰고 있다. 남은 시간이 [remaining_seconds] 다."""

    def __init__(self, remaining_seconds: int) -> None:
        super().__init__("이미 쓰고 있는 이모티콘이에요.")
        self.remaining_seconds = remaining_seconds


class TrainerRequired(EmoteError):
    """담당 트레이너가 없다 — 이모티콘을 보낼 트레이너 채팅이 없다."""


class EmoteLocked(EmoteError):
    """그 이모티콘을 사지 않았거나 기간이 끝났다."""


class UnknownEmote(EmoteError):
    """우리가 모르는 이모티콘이다."""


def is_known(emote_id: str) -> bool:
    return emote_id in EMOTE_IDS


def _active_pass(db: Session, member_id: str) -> EmotePass | None:
    """바뀌기 전에 산 24시간 이용권 중 아직 남은 것. 없으면 None."""
    return db.scalars(
        select(EmotePass)
        .where(EmotePass.user_id == member_id, EmotePass.expires_at > clock.now())
        .order_by(EmotePass.expires_at.desc())
        .limit(1)
    ).first()


def _unlocked_until(db: Session, member_id: str) -> dict[str, datetime]:
    """지금 쓸 수 있는 이모티콘과 각각 끝나는 시각."""
    now = clock.now()
    until: dict[str, datetime] = {}
    rows = db.execute(
        select(EmoteUnlock.emote_id, EmoteUnlock.expires_at).where(
            EmoteUnlock.user_id == member_id, EmoteUnlock.expires_at > now
        )
    ).all()
    for emote_id, expires_at in rows:
        if emote_id not in until or expires_at > until[emote_id]:
            until[emote_id] = expires_at
    legacy = _active_pass(db, member_id)
    if legacy is not None:
        for emote_id in EMOTE_IDS:
            if emote_id not in until or legacy.expires_at > until[emote_id]:
                until[emote_id] = legacy.expires_at
    return until


def _remaining_seconds(expires_at: datetime) -> int:
    return int((expires_at - clock.now()).total_seconds())


def state(db: Session, member_id: str) -> EmoteStateOut:
    """쓰고 있는 이모티콘과 값 — 고르는 창이 이것 하나로 그려진다."""
    unlocked = [
        EmoteUnlockOut(
            emote_id=emote_id,
            expires_at=expires_at.isoformat(),
            remaining_seconds=remaining,
        )
        for emote_id, expires_at in _unlocked_until(db, member_id).items()
        if (remaining := _remaining_seconds(expires_at)) > 0
    ]
    # 먼저 끝나는 것이 앞 — 순서가 매번 같아야 응답을 비교하기 쉽다.
    unlocked.sort(key=lambda u: (u.remaining_seconds, u.emote_id))
    return EmoteStateOut(
        unlocked=unlocked,
        cost=COST,
        days=DAYS,
        balance=points_service.balance(db, member_id),
    )


def require_unlocked(db: Session, member_id: str, emote_id: str) -> None:
    """회원이 그 이모티콘을 보낼 수 있는지 본다. 없으면 [EmoteLocked]."""
    if emote_id not in _unlocked_until(db, member_id):
        raise EmoteLocked("이 이모티콘을 먼저 사야 해요.")


def unlock(
    db: Session,
    member_id: str,
    emote_id: str,
    *,
    client_request_id: str | None = None,
) -> EmoteStateOut:
    """포인트를 써서 이모티콘 하나를 7일 동안 연다. 커밋한다.

    [client_request_id] 가 같은 재시도는 두 번 사지 않는다. 모르는 이모티콘이면
    [UnknownEmote], 담당 트레이너가 없으면 [TrainerRequired], 쓰고 있는 이모티콘이면
    [AlreadyUnlocked], 잔액이 모자라면 [points_service.InsufficientPoints] 다.
    """
    from app.services import trainer_service

    if not is_known(emote_id):
        raise UnknownEmote("없는 이모티콘이에요.")
    if client_request_id:
        existing = db.scalars(
            select(EmoteUnlock).where(
                EmoteUnlock.user_id == member_id,
                EmoteUnlock.client_request_id == client_request_id,
            )
        ).first()
        if existing is not None:
            return state(db, member_id)

    if trainer_service.get_member_trainer_id(db, member_id) is None:
        raise TrainerRequired("담당 트레이너가 있어야 쓸 수 있어요.")
    points_service.lock_balance(db, member_id)
    current = _unlocked_until(db, member_id).get(emote_id)
    if current is not None:
        remaining = _remaining_seconds(current)
        db.rollback()
        raise AlreadyUnlocked(max(remaining, 0))
    balance = points_service.balance(db, member_id)
    if balance < COST:
        db.rollback()
        raise points_service.InsufficientPoints(COST - balance)

    row = EmoteUnlock(
        id=f"emu-{uuid.uuid4().hex[:12]}",
        user_id=member_id,
        emote_id=emote_id,
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
            reason=REASON_EMOTE_UNLOCK,
            source_type=SOURCE_EMOTE_UNLOCK,
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
