"""트레이너 라우터 — 채팅(트레이너↔회원), 사진 메시지 포함."""
from __future__ import annotations

from datetime import datetime
from typing import Annotated

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    Query,
    UploadFile,
)
from sqlalchemy.orm import Session

from app.api.deps import RequireTrainer
from app.api.v1 import chat_attachments
from app.db.session import get_db
from app.schemas.text_limits import TEXT_LONG_MAX
from app.schemas.trainer_api import (
    ChatMessageOut, ChatSendRequest,
)
from app.services import (
    emote_service,
    notification_service,
    trainer_service,
)
from app.api.v1.trainer._common import (
    _require_client,
)


router = APIRouter(tags=["trainer"])


# ---- 채팅 (트레이너↔회원) ----


@router.get("/trainer/chat/unread", response_model=dict[str, int])
def trainer_chat_unread(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict[str, int]:
    """회원별 미확인 메시지 수(회원 발신·미읽음). 고객 목록 배지용.

    지금 담당 중이고 동의가 유효한 회원만 센다 — 해제·동의 철회 회원은
    읽음 처리(`_require_client`)가 404 라 지울 수 없는 숫자가 되기 때문이다(#2868).
    """
    return trainer_service.unread_counts_for_trainer(db, trainer.id)


@router.get("/trainer/clients/{member_id}/chat", response_model=list[ChatMessageOut])
def trainer_client_chat(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(50, ge=1, le=100, description="한 번에 가져올 최신 메시지 수"),
    before: str | None = Query(
        None, description="ISO datetime 커서 — 이전 페이지 요청(응답 created_at 사용)"
    ),
    before_id: str | None = Query(
        None, description="복합 커서 tie-break — 이전 페이지 가장 오래된 메시지의 id"
    ),
) -> list[ChatMessageOut]:
    """담당 고객과의 채팅 스레드(오래된→최신). 기본 최신 50건, (before, before_id)로 이전 페이지."""
    _require_client(db, trainer.id, member_id)
    before_dt: datetime | None = None
    if before:
        try:
            before_dt = datetime.fromisoformat(before)
        except ValueError as e:
            raise HTTPException(
                status_code=422, detail="before 는 ISO datetime 형식이어야 합니다."
            ) from e
    return trainer_service.build_chat_thread(
        db, trainer.id, member_id, limit=limit, before=before_dt, before_id=before_id
    )


@router.post("/trainer/clients/{member_id}/chat", response_model=ChatMessageOut, status_code=201)
def trainer_send_chat(
    member_id: str,
    payload: ChatSendRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ChatMessageOut:
    """트레이너가 담당 고객에게 메시지 발신."""
    _require_client(db, trainer.id, member_id)
    text = payload.text.strip()
    emote_id = payload.emote_id
    if emote_id is not None:
        # 트레이너는 이용권 없이 보낸다(#2020) — 이용권은 회원이 포인트를 쓰는
        # 자리이고, 트레이너에게는 포인트라는 것이 없다. 아는 id 인지만 본다.
        if not emote_service.is_known(emote_id):
            raise HTTPException(status_code=400, detail="없는 이모티콘이에요.")
        text = text or "(이모티콘)"
    if not text:
        raise HTTPException(status_code=400, detail="빈 메시지는 보낼 수 없습니다.")
    try:
        return trainer_service.send_message(
            db,
            trainer.id,
            member_id,
            "trainer",
            text,
            notify=notification_service.TRAINER_MESSAGE,
            client_request_id=payload.client_request_id,
            emote_id=emote_id,
        )
    except trainer_service.IdempotencyConflict as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post("/trainer/clients/{member_id}/chat/read")
def trainer_mark_chat_read(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """트레이너가 해당 고객 스레드를 읽음 처리."""
    _require_client(db, trainer.id, member_id)
    n = trainer_service.mark_thread_read(db, trainer.id, member_id, "trainer")
    return {"marked_read": n}


@router.post(
    "/trainer/clients/{member_id}/chat/image",
    response_model=ChatMessageOut,
    status_code=201,
)
def trainer_send_chat_image(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    image: UploadFile = File(...),
    message: str = Form("", max_length=TEXT_LONG_MAX),
    client_request_id: str | None = Form(None, min_length=1, max_length=64),
) -> ChatMessageOut:
    """담당 고객에게 사진을 보낸다. (#921)

    자세 사진·시범 이미지는 코칭에서 가장 자주 오가는 형식인데, 지금까지 채팅에
    붙일 수 있는 것은 주간 리포트 PDF 하나뿐이었다.

    형식은 **바이트를 보고 판정한다.** 확장자와 `Content-Type` 은 보내는 쪽이
    자유롭게 적을 수 있어, 그 말을 믿으면 `image/png` 라고 적힌 아무 파일이나
    저장된다.
    """
    _require_client(db, trainer.id, member_id)
    # 받는 규약은 회원 발신(#1665)과 한곳에서 나눠 쓴다. 동기 라우트라 DB·파일
    # 저장이 이벤트 루프가 아니라 스레드풀에서 돈다(#2835).
    return chat_attachments.receive_chat_image(
        db,
        trainer_id=trainer.id,
        member_id=member_id,
        sender="trainer",
        image=image,
        message=message,
        client_request_id=client_request_id,
        notify=notification_service.TRAINER_MESSAGE,
    )
