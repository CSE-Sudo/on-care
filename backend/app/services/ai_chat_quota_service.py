"""AI 챗봇 하루 대화 한도 — 무료 횟수와 포인트로 여는 추가 대화. (#2145)

AI 챗봇은 담당 트레이너가 없는 회원의 코치다. 메시지 한 번이 LLM 한 번이라, 하루
상한이 없으면 한 회원의 비용을 예측할 수 없다.

- **하루 무료** `coach_chat_free_per_day`(5) 번. KST 하루로 센다(#2217).
- 다 쓰면 **한 번에** `coach_chat_paid_cost`(50P) 로 하루 `coach_chat_paid_per_day`(10)
  번까지 더 보낸다. 식단 사진 한 장 적립과 같은 값이라 "사진 한 장 = 대화 한 번" 이다.
- 무료를 넘겨 보내려면 회원이 동의해야 한다(`pay_with_points`). 앱은 포인트로 보낼
  때마다 확인창을 띄운다(#2217) — 동의 없이 넘기면 [PointsConsentRequired].
- **AI 가 답했을 때만 센다.** 검색 기반 대체 답은 무료 횟수도 포인트도 쓰지 않는다.
  그래서 판정([plan])과 기록([record])을 나눈다 — LLM 을 부르기 전에 보낼 수 있는지
  보고, 답을 받은 뒤에야 센다.
- 같은 메시지의 재전송은 멱등키로 한 번만 센다([by_request]).
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core import clock
from app.core.config import get_settings
from app.models.models import AiChatUsage
from app.schemas.misc_api import AiChatQuotaOut
from app.services import points_service

#: 원장에 남는 사용 사유와 근거 종류.
REASON_AI_CHAT = "ai_chat"
SOURCE_AI_CHAT = "ai_chat"

NEXT_FREE = "free"
NEXT_PAID = "paid"
NEXT_EXHAUSTED = "exhausted"


class AiChatQuotaError(Exception):
    """AI 챗봇 한도 규칙 위반. 라우터가 상태코드로 옮긴다."""


class PointsConsentRequired(AiChatQuotaError):
    """오늘 무료 대화를 다 썼다 — 포인트로 보내려면 동의가 필요하다."""


class DailyLimitReached(AiChatQuotaError):
    """오늘 무료와 포인트 대화를 모두 썼다."""


@dataclass(frozen=True)
class _Used:
    free: int
    paid: int


def _limits() -> tuple[int, int, int]:
    s = get_settings()
    return s.coach_chat_free_per_day, s.coach_chat_paid_per_day, s.coach_chat_paid_cost


def _used_today(db: Session, user_id: str) -> _Used:
    rows = db.execute(
        select(AiChatUsage.paid, func.count())
        .where(
            AiChatUsage.user_id == user_id,
            AiChatUsage.kst_date == clock.today_iso(),
        )
        .group_by(AiChatUsage.paid)
    ).all()
    counts = {bool(paid): int(n) for paid, n in rows}
    return _Used(free=counts.get(False, 0), paid=counts.get(True, 0))


def status(db: Session, user_id: str) -> AiChatQuotaOut:
    """오늘 남은 무료·포인트 대화와 다음 대화가 무엇으로 나가는가."""
    free_limit, paid_limit, cost = _limits()
    used = _used_today(db, user_id)
    free_left = max(free_limit - used.free, 0)
    paid_left = max(paid_limit - used.paid, 0)
    return AiChatQuotaOut(
        free_limit=free_limit,
        free_left=free_left,
        paid_limit=paid_limit,
        paid_left=paid_left,
        cost=cost,
        balance=points_service.balance(db, user_id),
        next=NEXT_FREE if free_left else NEXT_PAID if paid_left else NEXT_EXHAUSTED,
    )


def plan(db: Session, user_id: str, *, pay_with_points: bool) -> bool:
    """이번 대화를 보낼 수 있는지 본다. 포인트로 나가면 True, 무료면 False.

    아무것도 쓰지 않는다 — LLM 이 답한 뒤에 [record] 가 센다. 오늘 다 썼으면
    [DailyLimitReached], 무료를 넘기는데 동의가 없으면 [PointsConsentRequired],
    잔액이 모자라면 [points_service.InsufficientPoints] 다.
    """
    quota = status(db, user_id)
    if quota.next == NEXT_FREE:
        return False
    if quota.next == NEXT_EXHAUSTED:
        raise DailyLimitReached("오늘 AI 코치 대화를 다 썼어요. 내일 다시 열려요.")
    if not pay_with_points:
        raise PointsConsentRequired(
            f"오늘 무료 대화를 다 썼어요. 한 번에 {quota.cost}P 로 더 보낼 수 있어요."
        )
    if quota.balance < quota.cost:
        raise points_service.InsufficientPoints(quota.cost - quota.balance)
    return True


def record(
    db: Session,
    user_id: str,
    *,
    paid: bool,
    message_id: str | None,
    client_request_id: str | None,
) -> AiChatUsage:
    """AI 가 답한 대화 한 번을 센다. 포인트로 나가면 차감한다. 커밋한다.

    판정([plan])과 답 사이에 다른 요청이 포인트를 썼으면 잔액이 모자랄 수 있다.
    그때는 답을 이미 준 뒤라 무료로 센다 — 회원이 받은 답을 빼앗을 수는 없고,
    같은 순간 두 번 보내는 일은 분당 한도가 막는다.
    """
    _, _, cost = _limits()
    row = AiChatUsage(
        id=f"aiu-{uuid.uuid4().hex[:12]}",
        user_id=user_id,
        kst_date=clock.today_iso(),
        paid=False,
        cost=0,
        message_id=message_id,
        client_request_id=client_request_id,
    )
    db.add(row)
    db.flush()
    if paid:
        try:
            row.balance_after = points_service.spend(
                db,
                user_id,
                reason=REASON_AI_CHAT,
                source_type=SOURCE_AI_CHAT,
                source_id=row.id,
                cost=cost,
            )
            row.paid = True
            row.cost = cost
        except points_service.InsufficientPoints:
            pass
    db.commit()
    db.refresh(row)
    return row


def by_request(
    db: Session, user_id: str, client_request_id: str
) -> AiChatUsage | None:
    """같은 멱등키로 이미 센 대화."""
    return db.scalar(
        select(AiChatUsage).where(
            AiChatUsage.user_id == user_id,
            AiChatUsage.client_request_id == client_request_id,
        )
    )


def spent_by_message(db: Session, message_ids: list[str]) -> dict[str, AiChatUsage]:
    """답변 id → 포인트로 산 대화. 저장된 대화의 차감 표시가 읽는다."""
    if not message_ids:
        return {}
    rows = db.scalars(
        select(AiChatUsage).where(
            AiChatUsage.message_id.in_(message_ids), AiChatUsage.paid.is_(True)
        )
    ).all()
    return {row.message_id: row for row in rows if row.message_id}
