"""트레이너 라우터 — AI 코칭(담당 고객 데이터 기반)."""
from __future__ import annotations

from typing import Annotated

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
)
from sqlalchemy.orm import Session

from app.api.deps import RequireTrainer
from app.core.config import get_settings
from app.core.rate_limit import (
    limiter,
)
from app.db.session import get_db
from app.schemas.trainer_api import (
    ClientCoachMessageOut, ClientCoachOut,
    ClientCoachRequest,
)
from app.services.coach import conversation
from app.services.coach.chat import answer as coach_answer
from app.api.v1.trainer._common import (
    _require_client,
)


router = APIRouter(tags=["trainer"])


# ---- AI 코칭 (담당 고객 데이터 기반) ----


@router.post("/trainer/clients/{member_id}/ai-coach", response_model=ClientCoachOut)
def trainer_client_ai_coach(
    member_id: str,
    payload: ClientCoachRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ClientCoachOut:
    """담당 고객의 데이터를 근거로 AI에게 코칭을 묻는다.

    회원 앱의 `/ai-coach/chat` 과 같은 RAG 파이프라인이지만, 검색 스코프가
    호출자(트레이너)가 아니라 **담당 회원**이다 — 트레이너가 자기 자신의 (비어
    있는) 기록으로 코칭받는 일이 없도록. 담당 링크 확인이 접근 경계이며,
    남의 고객이면 404 로 존재조차 드러내지 않는다.

    **분당 한도(#1548)** — 회원 AI 코치와 같은 `coach_chat_per_minute` 를 트레이너
    단위 버킷으로 센다. 넘기면 429 와 `Retry-After` 다. 같은 헬스장(같은 IP)의 다른
    트레이너가 한도를 대신 소진하지 않게 IP 가 아니라 트레이너 id 로 나눈다.

    **하루 상한(#3032)** — 이 트레이너의 고객 AI 코칭·루틴 후보·리포트 요약 합이
    `trainer_ai_calls_per_day` 를 넘으면 429 `daily_limit` + `Retry-After`(다음 KST
    자정까지)다. 서버 전체 상한에 걸리면 503 `ai_capacity` 다. 둘 다 모델을 부르지
    않았고 대화도 저장하지 않는다.
    """
    _require_client(db, trainer.id, member_id)
    settings = get_settings()
    if settings.rate_limit_enabled:
        limiter.check(
            f"trainer-coach-chat:trainer:{trainer.id}",
            settings.coach_chat_per_minute,
            60.0,
        )
    message = payload.message.strip()
    if not message:
        raise HTTPException(status_code=400, detail="메시지가 비어 있습니다.")

    # 이 트레이너 전용 스레드다(#588). 검색 스코프는 회원이지만 문답의 주인은
    # 트레이너라, 회원 대화(trainer_id IS NULL)와 섞이면 회원이 앱을 열었을 때
    # 자기가 하지 않은 대화를 보게 된다.
    history = conversation.load_messages(db, member_id, trainer_id=trainer.id)
    reply, sources, _ = coach_answer(
        db, member_id, message, history, trainer_id=trainer.id
    )
    conversation.append_exchange(
        db, member_id, question=message, reply=reply, sources=sources,
        trainer_id=trainer.id,
    )
    return ClientCoachOut(member_id=member_id, reply=reply, sources=sources)


@router.get(
    "/trainer/clients/{member_id}/ai-coach",
    response_model=list[ClientCoachMessageOut],
)
def trainer_client_ai_coach_history(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[ClientCoachMessageOut]:
    """이 트레이너가 해당 고객에 대해 나눈 문답 복원(오래된→최신).

    시트를 닫았다 열면 대화가 사라지던 문제를 없앤다. 다른 트레이너의 문답은
    스레드가 달라 보이지 않는다.
    """
    _require_client(db, trainer.id, member_id)
    rows = conversation.load_messages(db, member_id, trainer_id=trainer.id)
    return [
        ClientCoachMessageOut(
            role=m.role,
            content=m.content,
            sources=conversation.parse_sources(m.sources_json),
        )
        for m in rows
    ]
