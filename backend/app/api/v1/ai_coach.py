"""
AI 코치 라우터 — 프론트 계약 정렬.

  GET  /ai-coach/feedback  -> { greeting, suggestions[] }
  GET  /ai-coach/messages  -> 저장된 대화 복원
  POST /ai-coach/chat      -> RAG 근거 기반 답변 + 대화 저장
  GET  /ai-coach/insights  -> 최근 30일 회원 메시지의 통증·부정적 반응 감지 기록 (#1824)
  DELETE /ai-coach/insights/{message_id} -> 그 줄의 감지를 기록에서 치움 (#1975)

도메인(식단/운동)별 코치를 각각 생성해 합친 결과.
STEP 7에서 내부가 RAG+LLM 으로 교체되지만 응답 형식은 동일.
"""
from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser
from app.core.config import get_settings
from app.core.rate_limit import rate_limit
from app.db.session import get_db
from app.models.models import AiConversation, AiMessage
from app.schemas.misc_api import (
    AiChatQuotaOut,
    AiCoachFeedback,
    ChatHistory,
    ChatInsightList,
    ChatInsightOut,
    ChatInsightRecordOut,
    ChatMessageOut,
    ChatReply,
    ChatRequest,
)
from app.services import ai_chat_quota_service, points_service
from app.services.coach import conversation, insights
from app.services.coach.chat import answer
from app.services.coach_service import build_feedback
from app.services.trainer_service import get_member_trainer_id

router = APIRouter(tags=["ai-coach"])

#: 담당 트레이너가 연결된 회원에게 AI 챗봇 경로가 돌려주는 안내. (#1823)
TRAINER_CONNECTED_DETAIL = "담당 트레이너가 연결된 회원은 AI 챗봇 대신 트레이너 채팅을 이용합니다."


def _ensure_ai_chat_allowed(db: Session, user_id: str) -> None:
    """담당 트레이너가 있는 회원은 AI 챗봇을 쓰지 않는다 — 403. (#1823)

    앱은 이 회원에게 AI 챗봇 입구를 보이지 않지만, 입구를 숨기는 것만으로는 막히지
    않는다(열어 둔 화면·직접 호출). 판정은 '현재 담당' 의 단일 소스인 활성 담당
    링크를 따른다 — 휴면 링크만 남은 회원은 담당이 없는 회원이라 AI 챗봇을 쓴다.
    """
    if get_member_trainer_id(db, user_id) is not None:
        raise HTTPException(status_code=403, detail=TRAINER_CONNECTED_DETAIL)


@router.get("/ai-coach/feedback", response_model=AiCoachFeedback)
def ai_coach_feedback(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> AiCoachFeedback:
    return build_feedback(db, current_user.id, current_user.name)


@router.get("/ai-coach/messages", response_model=ChatHistory)
def ai_coach_messages(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> ChatHistory:
    """저장된 대화 복원 — 재접속·다기기에서 히스토리를 잇는다.

    아직 한 마디도 나누지 않았으면 빈 목록이다(이 경로는 대화 스레드를 만들지 않는다).
    최근 30일 대화만 준다. 담당 트레이너가 있는 회원은 403 이다(#1823).
    """
    _ensure_ai_chat_allowed(db, current_user.id)
    rows = conversation.load_messages(db, current_user.id)
    # 포인트로 산 답변 아래에 차감을 다시 그린다(#2145).
    paid = ai_chat_quota_service.spent_by_message(db, [m.id for m in rows])
    return ChatHistory(
        messages=[
            ChatMessageOut(
                role=m.role,
                content=m.content,
                sources=conversation.parse_sources(m.sources_json),
                created_at=m.created_at,
                insight=_insight_out(m.content) if m.role == "user" else None,
                points_spent=paid[m.id].cost if m.id in paid else 0,
                balance_after=paid[m.id].balance_after if m.id in paid else None,
            )
            for m in rows
        ]
    )


@router.get("/ai-coach/quota", response_model=AiChatQuotaOut)
def ai_coach_quota(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> AiChatQuotaOut:
    """오늘 남은 무료·포인트 대화와 다음 대화가 무엇으로 나가는가(#2145).

    입력칸 위 줄이 이것 하나로 그려진다. 담당 트레이너가 있는 회원은 403 이다.
    """
    _ensure_ai_chat_allowed(db, current_user.id)
    return ai_chat_quota_service.status(db, current_user.id)


@router.post(
    "/ai-coach/chat",
    response_model=ChatReply,
    dependencies=[
        Depends(rate_limit("coach-chat", get_settings().coach_chat_per_minute))
    ],
)
def ai_coach_chat(
    payload: ChatRequest,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> ChatReply:
    """대화형 코칭: RAG 근거 기반 답변(개인/공공 격리). LLM 키 없으면 검색 기반 폴백.

    대화는 서버에 저장된다. 히스토리도 서버 저장분을 우선 쓰므로 클라이언트가
    `history` 를 보내지 않아도 맥락이 이어진다. 다만 저장분이 아직 없을 때는
    요청에 실려 온 `history` 를 쓴다 — 목업 모드로 대화하다 실 서버로 전환한
    클라이언트의 맥락을 버리지 않기 위해서다.

    **하루 한도(#2145)** — 무료를 다 쓴 뒤에는 `pay_with_points` 동의가 있어야
    포인트로 보낸다. 동의가 없으면 402(`points_required`), 오늘 다 썼으면
    429(`daily_limit`), 잔액이 모자라면 409(`insufficient_points`)다. `detail` 은
    `{code, message}` 이고 모자라면 `shortfall` 도 싣는다. AI 가 답했을 때만 세고
    차감한다. 같은 `client_request_id` 재전송은 저장한 답을 그대로 돌려준다.
    """
    _ensure_ai_chat_allowed(db, current_user.id)
    message = payload.message.strip()
    if not message:
        raise HTTPException(status_code=400, detail="메시지가 비어 있습니다.")

    if payload.client_request_id:
        replay = _replay(db, current_user.id, payload.client_request_id, message)
        if replay is not None:
            return replay

    try:
        paid = ai_chat_quota_service.plan(
            db, current_user.id, pay_with_points=payload.pay_with_points
        )
    except ai_chat_quota_service.PointsConsentRequired as exc:
        raise HTTPException(
            status_code=402, detail={"code": "points_required", "message": str(exc)}
        ) from exc
    except ai_chat_quota_service.DailyLimitReached as exc:
        raise HTTPException(
            status_code=429, detail={"code": "daily_limit", "message": str(exc)}
        ) from exc
    except points_service.InsufficientPoints as exc:
        raise HTTPException(
            status_code=409,
            detail={
                "code": "insufficient_points",
                "message": str(exc),
                "shortfall": exc.shortfall,
            },
        ) from exc

    stored = conversation.load_messages(db, current_user.id)
    history = stored or payload.history

    reply, sources, generated = answer(db, current_user.id, message, history)
    convo = conversation.append_exchange(
        db, current_user.id, question=message, reply=reply, sources=sources
    )
    spent = 0
    balance_after: int | None = None
    if generated:
        usage = ai_chat_quota_service.record(
            db,
            current_user.id,
            paid=paid,
            message_id=conversation.last_reply_id(db, convo),
            client_request_id=payload.client_request_id,
        )
        spent = usage.cost
        balance_after = usage.balance_after
    return ChatReply(
        reply=reply,
        sources=sources,
        user_insight=_insight_out(message),
        points_spent=spent,
        balance_after=balance_after,
        quota=ai_chat_quota_service.status(db, current_user.id),
    )


def _replay(
    db: Session, user_id: str, client_request_id: str, message: str
) -> ChatReply | None:
    """같은 멱등키로 이미 답한 대화면 그 답을 그대로 돌려준다(#2145).

    응답을 못 받고 다시 보낸 메시지가 두 번 세지거나 두 번 차감되지 않는다.
    답변이 한 달이 지나 지워졌으면 다시 답한다(그때는 새로 센다).
    """
    usage = ai_chat_quota_service.by_request(db, user_id, client_request_id)
    if usage is None or usage.message_id is None:
        return None
    row = db.get(AiMessage, usage.message_id)
    if row is None:
        return None
    return ChatReply(
        reply=row.content,
        sources=conversation.parse_sources(row.sources_json),
        user_insight=_insight_out(message),
        points_spent=usage.cost,
        balance_after=usage.balance_after,
        quota=ai_chat_quota_service.status(db, user_id),
    )


def _insight_out(text: str) -> ChatInsightOut | None:
    """회원 문장 하나의 감지 결과를 응답 모양으로. 신호가 없으면 None."""
    found = insights.detect(text)
    if found is None:
        return None
    return ChatInsightOut(kind=found.kind, body_part=found.body_part)


@router.get("/ai-coach/insights", response_model=ChatInsightList)
def ai_coach_insights(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> ChatInsightList:
    """최근 30일 동안 AI 챗봇에 회원이 쓴 메시지의 통증·부정적 반응 감지 기록. (#1824)

    트레이너 채팅의 감지와 같은 규칙이다. 결과는 저장하지 않고 대화에서 매번 계산한다.
    AI 챗봇의 일부라 담당 트레이너가 있는 회원은 403 이다(#1823).
    """
    _ensure_ai_chat_allowed(db, current_user.id)
    records = insights.recent_insights(db, current_user.id)
    return ChatInsightList(
        window_days=insights.INSIGHT_WINDOW_DAYS,
        insights=[
            ChatInsightRecordOut(
                message_id=r.message_id,
                created_at=r.created_at,
                kind=r.kind,
                body_part=r.body_part,
                text=r.text,
            )
            for r in records
        ],
    )


@router.delete("/ai-coach/insights/{message_id}")
def dismiss_ai_coach_insight(
    message_id: str,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """그 줄에서 찾은 감지를 기록에서 치운다. (#1975)

    **메시지는 지우지 않는다.** 감지 규칙이 완벽할 수 없어 `목요일`·`목표` 같은
    말이 부위로 잡히는 일이 남는데, 그 오탐 하나 때문에 회원이 쓴 말까지 대화에서
    사라져서는 안 된다. 치우는 것은 감지뿐이고, AI 가 맥락으로 읽는 대화는 그대로다.

    감지를 따로 저장하지 않으므로(매번 계산) 지울 행이 없다 — 대신 그 메시지에
    `더 보지 않음` 표시를 남기고 `recent_insights` 가 건너뛴다.

    이미 치운 줄을 다시 눌러도 200 이다. 누른 쪽이 바라는 상태가 이미 참이라,
    지금 상태를 알려 주는 것 말고 할 일이 없다.
    """
    _ensure_ai_chat_allowed(db, current_user.id)
    message = db.scalar(
        select(AiMessage)
        .join(AiConversation, AiConversation.id == AiMessage.conversation_id)
        .where(
            AiMessage.id == message_id,
            AiConversation.user_id == current_user.id,
            AiMessage.role == "user",
        )
    )
    # 남의 대화는 물론이고 없는 id 도 404 다 — 있는지 없는지를 알려 주지 않는다.
    if message is None:
        raise HTTPException(status_code=404, detail="감지 기록을 찾을 수 없습니다.")
    message.insight_dismissed = True
    db.commit()
    return {"status": "dismissed"}
