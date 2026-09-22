"""
AI 코치 대화 영속화.

`/ai-coach/chat` 은 원래 무상태였다. 히스토리를 클라가 매번 실어 보내는 구조라
앱을 다시 켜거나 다른 기기로 옮기면 대화가 사라졌다(#274). 여기서 대화를 서버에
저장하고 복원한다.

설계 메모:
- 앱에는 대화 목록 UI 가 없고 채팅 시트 하나만 있다. 그래서 사용자당 **활성 스레드
  1개**를 get-or-create 해서 쓴다. 스레드 개념 자체는 테이블로 분리해 뒀으므로,
  나중에 목록이 필요해지면 archived_at 을 채우는 것으로 확장된다.
- 저장은 요청 단위로 사용자 메시지 + 코치 답변을 함께 커밋한다. 답변 생성이
  실패해도 폴백 문구가 반환되므로 "질문만 남고 답이 없는" 상태는 생기지 않는다.
- 근거 문서 제목(sources)은 답변과 함께 저장한다. 복원했을 때 근거가 사라지면
  왜 그렇게 답했는지 되짚을 수 없다.
"""
from __future__ import annotations

import json
import uuid
from datetime import datetime, timedelta

from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import AiConversation, AiMessage

#: 한 대화에서 복원·프롬프트에 쓰는 최대 메시지 수. 오래된 대화가 길어져도
#: 프롬프트가 무한정 커지지 않게 막는다(비용·지연 가드).
MAX_HISTORY_MESSAGES = 50

#: 회원 본인 AI 챗봇 대화를 보관하는 기간(일). (#1823)
#:
#: 이보다 오래된 메시지는 복원·프롬프트에 쓰지 않고, 새 대화를 저장할 때 지운다.
#: 트레이너가 회원에 대해 AI 에게 묻는 스레드(`trainer_id` 있음)는 대상이 아니다 —
#: 그 기록은 트레이너 쪽 기능이라 회원 챗봇의 보관 규칙을 따르지 않는다.
HISTORY_RETENTION_DAYS = 30

ROLE_USER = "user"
ROLE_COACH = "coach"


def retention_cutoff(now: datetime | None = None) -> datetime:
    """이 시각보다 먼저 쓴 회원 AI 챗봇 메시지는 보관 기간이 지났다."""
    return (now or clock.now()) - timedelta(days=HISTORY_RETENTION_DAYS)


def purge_expired_messages(
    db: Session, user_id: str, *, now: datetime | None = None
) -> int:
    """회원 본인 스레드에서 보관 기간이 지난 메시지를 지운다. 지운 개수를 돌려준다.

    커밋은 호출자가 한다 — 새 대화 저장과 한 트랜잭션으로 묶어, 지우기만 하고
    저장이 실패하는 반쪽 상태를 만들지 않는다.
    """
    own_threads = select(AiConversation.id).where(
        AiConversation.user_id == user_id, AiConversation.trainer_id.is_(None)
    )
    result = db.execute(
        delete(AiMessage)
        .where(
            AiMessage.conversation_id.in_(own_threads),
            AiMessage.created_at < retention_cutoff(now),
        )
        .execution_options(synchronize_session=False)
    )
    return result.rowcount or 0


def _new_id(prefix: str) -> str:
    return f"{prefix}-{uuid.uuid4().hex[:16]}"


def _active_thread_filter(user_id: str, trainer_id: str | None):
    """스레드 식별 조건 — (회원, 화자) 쌍이 스레드를 가른다(#588).

    `trainer_id` 가 NULL 인 스레드가 회원 본인의 대화다. 이 조건을 한 곳에 모아
    두는 이유: 조회와 생성이 조건을 다르게 쓰면 매 요청이 새 스레드를 만들거나,
    더 나쁘게는 트레이너 질의가 회원 대화에 섞인다.
    """
    owner = (
        AiConversation.trainer_id.is_(None)
        if trainer_id is None
        else AiConversation.trainer_id == trainer_id
    )
    return (
        AiConversation.user_id == user_id,
        owner,
        AiConversation.archived_at.is_(None),
    )


def get_or_create_active(
    db: Session, user_id: str, *, trainer_id: str | None = None
) -> AiConversation:
    """활성 대화 스레드. 없으면 만든다.

    [trainer_id] 가 있으면 그 트레이너가 이 회원에 대해 묻는 전용 스레드다.
    """
    convo = db.scalar(
        select(AiConversation)
        .where(*_active_thread_filter(user_id, trainer_id))
        .order_by(AiConversation.created_at.desc())
        .limit(1)
    )
    if convo is not None:
        return convo

    convo = AiConversation(
        id=_new_id("aiconv"), user_id=user_id, trainer_id=trainer_id
    )
    db.add(convo)
    try:
        db.commit()
    except IntegrityError:
        # 같은 (회원, 트레이너) 요청이 동시에 생성되면 부분 유니크 인덱스에서
        # 한쪽만 이긴다. 실패한 세션을 정리한 뒤 승자가 만든 스레드를 반환한다.
        db.rollback()
        winner = db.scalar(
            select(AiConversation)
            .where(*_active_thread_filter(user_id, trainer_id))
            .order_by(AiConversation.created_at.desc())
            .limit(1)
        )
        if winner is None:
            # FK 위반 등 활성 스레드 경쟁이 아닌 무결성 오류는 숨기지 않는다.
            raise
        return winner
    db.refresh(convo)
    return convo


def load_messages(
    db: Session, user_id: str, *, trainer_id: str | None = None
) -> list[AiMessage]:
    """활성 대화의 메시지를 시간순으로. 대화가 없으면 빈 목록.

    스레드를 만들지 않는 조회 전용 경로다. 채팅 화면을 열기만 하고 아무 말도 하지
    않은 사용자에게 빈 대화 레코드를 남기지 않는다.

    회원 본인 스레드는 보관 기간(`HISTORY_RETENTION_DAYS`) 안의 메시지만 준다(#1823).
    지우는 일은 저장 경로가 하지만, 한동안 말을 걸지 않은 회원에게도 지난 대화가
    복원·프롬프트에 섞이지 않게 조회에서도 같은 선을 긋는다.
    """
    convo = db.scalar(
        select(AiConversation)
        .where(*_active_thread_filter(user_id, trainer_id))
        .order_by(AiConversation.created_at.desc())
        .limit(1)
    )
    if convo is None:
        return []

    conditions = [AiMessage.conversation_id == convo.id]
    if trainer_id is None:
        conditions.append(AiMessage.created_at >= retention_cutoff())
    rows = db.scalars(
        select(AiMessage).where(*conditions).order_by(AiMessage.seq.asc())
    ).all()
    return list(rows)[-MAX_HISTORY_MESSAGES:]


def append_exchange(
    db: Session,
    user_id: str,
    *,
    question: str,
    reply: str,
    sources: list[str],
    trainer_id: str | None = None,
) -> AiConversation:
    """질문과 답변을 한 번에 저장한다.

    두 줄을 한 커밋으로 묶어야 중간에 실패했을 때 질문만 남는 반쪽 대화가 생기지
    않는다. 순서는 `seq` 로 고정한다 — created_at 은 쓸 수 없다. PostgreSQL 의
    now() 는 트랜잭션 시각이라 같은 커밋의 두 줄이 **동일한 created_at** 을 갖고,
    그러면 정렬이 랜덤한 id 순으로 무너져 답변이 질문보다 먼저 보인다.
    """
    convo = get_or_create_active(db, user_id, trainer_id=trainer_id)
    # 대화 한 행을 순번 할당용 mutex 로 쓴다. PostgreSQL 에서는 같은 스레드의
    # 동시 append 가 여기서 직렬화되므로 max(seq)를 읽고 두 메시지를 커밋할 때까지
    # 다른 요청이 같은 순번을 가져갈 수 없다.
    convo = db.scalar(
        select(AiConversation)
        .where(AiConversation.id == convo.id)
        .with_for_update()
    )
    if convo is None:
        raise RuntimeError("활성 AI 대화 스레드가 저장 중 삭제되었습니다.")
    # 빈 대화면 max 가 NULL 이라 coalesce 로 -1 → 첫 순번이 0 이 된다.
    next_seq = db.scalar(
        select(func.coalesce(func.max(AiMessage.seq), -1) + 1).where(
            AiMessage.conversation_id == convo.id
        )
    )

    db.add(
        AiMessage(
            id=_new_id("aimsg"),
            conversation_id=convo.id,
            seq=next_seq,
            role=ROLE_USER,
            content=question,
            sources_json="[]",
        )
    )
    db.add(
        AiMessage(
            id=_new_id("aimsg"),
            conversation_id=convo.id,
            seq=next_seq + 1,
            role=ROLE_COACH,
            content=reply,
            sources_json=json.dumps(sources, ensure_ascii=False),
        )
    )
    if trainer_id is None:
        # 회원 본인 대화는 한 달만 남긴다(#1823). 저장과 같은 커밋으로 지운다.
        purge_expired_messages(db, user_id)
    db.commit()
    return convo


def last_reply_id(db: Session, convo: AiConversation) -> str | None:
    """대화의 마지막 코치 답변 id. 방금 저장한 답을 가리킬 때 쓴다(#2145)."""
    return db.scalar(
        select(AiMessage.id)
        .where(AiMessage.conversation_id == convo.id, AiMessage.role == ROLE_COACH)
        .order_by(AiMessage.seq.desc())
        .limit(1)
    )


def parse_sources(raw: str) -> list[str]:
    """저장된 sources_json → 리스트. 깨진 값이면 빈 목록(화면이 죽으면 안 된다)."""
    try:
        value = json.loads(raw or "[]")
    except (TypeError, ValueError):
        return []
    if not isinstance(value, list):
        return []
    return [str(v) for v in value]
