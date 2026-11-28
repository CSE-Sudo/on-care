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
- 스레드는 회원 본인 대화(`trainer_id IS NULL`)만 만든다. 트레이너가 회원에 대해
  AI 에게 묻던 API(#588)는 지웠고(#3085), 남아 있을 수 있는 그 스레드는 회원
  대화를 읽는 모든 조회가 [member_thread_clause] 로 건너뛴다.
"""
from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
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
HISTORY_RETENTION_DAYS = 30

ROLE_USER = "user"
ROLE_COACH = "coach"


@dataclass(frozen=True)
class Exchange:
    """한 번의 전송이 남긴 질문과 답 — 응답이 두 줄의 식별자·저장 시각을 싣는다. (#3352)"""

    conversation: AiConversation
    question: AiMessage
    reply: AiMessage


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
        AiConversation.user_id == user_id, member_thread_clause()
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


def member_thread_clause():
    """회원 본인 대화 스레드인지 — `trainer_id` 가 NULL 이다(#588, #3085).

    예전에는 트레이너가 회원에 대해 AI 에게 물은 문답이 `user_id=회원`,
    `trainer_id=트레이너` 스레드에 `role="user"` 로 남았다. 회원 대화를 읽는 곳
    (복원·보관 정리·불편 감지·감지 치우기·트레이너 통증 신호)이 `user_id` 만 보면
    트레이너가 한 말이 회원 발화로 읽힌다. 그래서 모두 이 조건을 함께 건다.
    """
    return AiConversation.trainer_id.is_(None)


def _active_thread_filter(user_id: str):
    """회원 활성 스레드 식별 조건.

    조회와 생성이 조건을 다르게 쓰면 매 요청이 새 스레드를 만들거나, 다른 스레드의
    말이 회원 대화에 섞인다. 그래서 한 곳에 모은다.
    """
    return (
        AiConversation.user_id == user_id,
        member_thread_clause(),
        AiConversation.archived_at.is_(None),
    )


def get_or_create_active(db: Session, user_id: str) -> AiConversation:
    """회원의 활성 대화 스레드. 없으면 만든다."""
    convo = db.scalar(
        select(AiConversation)
        .where(*_active_thread_filter(user_id))
        .order_by(AiConversation.created_at.desc())
        .limit(1)
    )
    if convo is not None:
        return convo

    convo = AiConversation(id=_new_id("aiconv"), user_id=user_id)
    db.add(convo)
    try:
        db.commit()
    except IntegrityError:
        # 같은 회원의 요청이 동시에 생성되면 부분 유니크 인덱스에서
        # 한쪽만 이긴다. 실패한 세션을 정리한 뒤 승자가 만든 스레드를 반환한다.
        db.rollback()
        winner = db.scalar(
            select(AiConversation)
            .where(*_active_thread_filter(user_id))
            .order_by(AiConversation.created_at.desc())
            .limit(1)
        )
        if winner is None:
            # FK 위반 등 활성 스레드 경쟁이 아닌 무결성 오류는 숨기지 않는다.
            raise
        return winner
    db.refresh(convo)
    return convo


def load_messages(db: Session, user_id: str) -> list[AiMessage]:
    """활성 대화의 메시지를 시간순으로. 대화가 없으면 빈 목록.

    스레드를 만들지 않는 조회 전용 경로다. 채팅 화면을 열기만 하고 아무 말도 하지
    않은 사용자에게 빈 대화 레코드를 남기지 않는다.

    보관 기간(`HISTORY_RETENTION_DAYS`) 안의 메시지만 준다(#1823).
    지우는 일은 저장 경로가 하지만, 한동안 말을 걸지 않은 회원에게도 지난 대화가
    복원·프롬프트에 섞이지 않게 조회에서도 같은 선을 긋는다.
    """
    convo = db.scalar(
        select(AiConversation)
        .where(*_active_thread_filter(user_id))
        .order_by(AiConversation.created_at.desc())
        .limit(1)
    )
    if convo is None:
        return []

    rows = db.scalars(
        select(AiMessage)
        .where(
            AiMessage.conversation_id == convo.id,
            AiMessage.created_at >= retention_cutoff(),
        )
        .order_by(AiMessage.seq.asc())
    ).all()
    return list(rows)[-MAX_HISTORY_MESSAGES:]


def append_exchange(
    db: Session,
    user_id: str,
    *,
    question: str,
    reply: str,
    sources: list[str],
    client_request_id: str | None = None,
) -> Exchange:
    """질문과 답변을 한 번에 저장한다. 저장한 두 줄을 돌려준다.

    두 줄을 한 커밋으로 묶어야 중간에 실패했을 때 질문만 남는 반쪽 대화가 생기지
    않는다. 순서는 `seq` 로 고정한다 — created_at 은 쓸 수 없다. PostgreSQL 의
    now() 는 트랜잭션 시각이라 같은 커밋의 두 줄이 **동일한 created_at** 을 갖고,
    그러면 정렬이 랜덤한 id 순으로 무너져 답변이 질문보다 먼저 보인다.

    `client_request_id` 는 두 줄에 함께 남긴다(#3352). 대체 답으로 끝난 전송은 사용
    기록이 남지 않아, 같은 키의 재전송을 알아볼 근거가 이 값뿐이다([exchange_by_request]).
    """
    convo = get_or_create_active(db, user_id)
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

    question_row = AiMessage(
        id=_new_id("aimsg"),
        conversation_id=convo.id,
        seq=next_seq,
        role=ROLE_USER,
        content=question,
        sources_json="[]",
        client_request_id=client_request_id,
    )
    reply_row = AiMessage(
        id=_new_id("aimsg"),
        conversation_id=convo.id,
        seq=next_seq + 1,
        role=ROLE_COACH,
        content=reply,
        sources_json=json.dumps(sources, ensure_ascii=False),
        client_request_id=client_request_id,
    )
    db.add(question_row)
    db.add(reply_row)
    # 회원 대화는 한 달만 남긴다(#1823). 저장과 같은 커밋으로 지운다.
    purge_expired_messages(db, user_id)
    db.commit()
    # 저장 시각은 DB 가 찍는다 — 응답에 싣기 전에 다시 읽는다.
    db.refresh(question_row)
    db.refresh(reply_row)
    return Exchange(conversation=convo, question=question_row, reply=reply_row)


def exchange_by_request(
    db: Session, user_id: str, client_request_id: str
) -> Exchange | None:
    """이 멱등키의 전송이 회원 대화에 남긴 질문과 답. 없으면 None. (#3352)

    AI 가 답했든 대체 답이었든 저장된 전송이면 찾는다. 보관 기간이 지난 줄은 없는
    것으로 본다 — 조회·프롬프트가 쓰지 않는 대화를 재생하지 않는다.
    """
    rows = db.scalars(
        select(AiMessage)
        .join(AiConversation, AiConversation.id == AiMessage.conversation_id)
        .where(
            AiConversation.user_id == user_id,
            member_thread_clause(),
            AiMessage.client_request_id == client_request_id,
            AiMessage.created_at >= retention_cutoff(),
        )
        .order_by(AiMessage.seq.asc())
    ).all()
    question = next((m for m in rows if m.role == ROLE_USER), None)
    reply = next((m for m in rows if m.role == ROLE_COACH), None)
    if question is None or reply is None:
        return None
    convo = db.get(AiConversation, reply.conversation_id)
    if convo is None:  # pragma: no cover - 줄이 있으면 스레드도 있다(FK)
        return None
    return Exchange(conversation=convo, question=question, reply=reply)


def question_of(db: Session, reply: AiMessage) -> AiMessage | None:
    """코치 답 바로 앞의 회원 질문 — 같은 전송이 남긴 줄이다. 없으면 None.

    멱등키를 메시지에 남기기 전(#3352)에 저장된 답을 재생할 때, 그 질문의 식별자를
    함께 돌려주려고 순번으로 찾는다.
    """
    return db.scalar(
        select(AiMessage).where(
            AiMessage.conversation_id == reply.conversation_id,
            AiMessage.seq == reply.seq - 1,
            AiMessage.role == ROLE_USER,
        )
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
