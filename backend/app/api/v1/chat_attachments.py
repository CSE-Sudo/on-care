"""Authenticated access to the file carried by a chat message.

주간 리포트 PDF(#778)로 시작해 코칭 사진(#921)이 더해졌다. 두 종류가 한 경로를
쓰는 이유는 **권한 판단이 같기 때문이다** — 그 스레드의 두 사람만 볼 수 있다.
경로를 나누면 그 판단이 두 벌이 되고, 한쪽만 고쳐지는 날이 온다.

사진을 **받아 저장하는** 규약도 여기 둔다([receive_chat_image]). 트레이너가
보내는 사진(#921)과 회원이 보내는 사진(#1665)은 보내는 사람만 다르고 형식 판정·
용량 상한·멱등 처리·고립 파일 정리가 모두 같다. 두 벌로 두면 한쪽만 느슨해진다.
"""
from __future__ import annotations

import re
from pathlib import PurePath
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, UploadFile
from sqlalchemy import select
from sqlalchemy.orm import Session
from starlette.responses import FileResponse

from app.api.deps import RequireUser
from app.core.config import get_settings
from app.db.session import get_db
from app.models.models import ChatMessage, TrainerClient
from app.schemas.trainer_api import ChatMessageOut
from app.services import chat_image_storage, report_pdf_storage, trainer_service

router = APIRouter(tags=["chat-attachments"])

#: 어느 종류든 "찾을 수 없습니다" 로 끝난다. 권한이 없는 사람에게 파일의
#: 존재 여부를 알려 주지 않기 위해서다.
_NOT_FOUND = "첨부를 찾을 수 없습니다."


@router.get("/chat/attachments/{file_id}")
def download_chat_attachment(
    file_id: str,
    user: RequireUser,
    db: Annotated[Session, Depends(get_db)],
) -> FileResponse:
    message = db.scalar(
        select(ChatMessage).where(
            ChatMessage.attachment_file_id == file_id,
            ChatMessage.attachment_type.in_(("pdf", "image")),
        )
    )
    if message is None:
        raise HTTPException(status_code=404, detail=_NOT_FOUND)

    allowed = user.role == "member" and message.member_id == user.id
    if user.role == "trainer" and message.trainer_id == user.id:
        allowed = db.scalar(
            select(TrainerClient.id).where(
                TrainerClient.trainer_id == user.id,
                TrainerClient.member_id == message.member_id,
                TrainerClient.active.is_(True),
            )
        ) is not None
    if not allowed:
        # 다른 사용자에게 file id의 존재 여부를 노출하지 않는다.
        raise HTTPException(status_code=404, detail=_NOT_FOUND)

    if message.attachment_type == "image":
        try:
            path, media_type = chat_image_storage.path_for(file_id)
        except FileNotFoundError as exc:
            raise HTTPException(status_code=404, detail=_NOT_FOUND) from exc
        # 사진은 대화 안에서 그려야 한다 — `attachment` 로 주면 브라우저가
        # 내려받기로 처리해 스레드에 아무것도 보이지 않는다.
        return FileResponse(
            path,
            media_type=media_type,
            filename=message.attachment_file_name or "photo",
            content_disposition_type="inline",
        )

    try:
        path = report_pdf_storage.path_for(file_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=_NOT_FOUND) from exc
    return FileResponse(
        path,
        media_type="application/pdf",
        filename=message.attachment_file_name or "weekly-report.pdf",
        content_disposition_type="attachment",
    )


async def receive_chat_image(
    db: Session,
    *,
    trainer_id: str,
    member_id: str,
    sender: Literal["trainer", "member"],
    image: UploadFile,
    message: str,
    client_request_id: str | None,
    notify: str | None = None,
) -> ChatMessageOut:
    """사진 한 장을 스레드에 붙여 보낸다 — 트레이너(#921)·회원(#1665) 공용.

    담당 관계 확인은 **호출자가 먼저 한다.** 누가 누구에게 보낼 수 있는지는
    보내는 쪽마다 다르지만(트레이너는 담당 고객에게, 회원은 담당 트레이너에게),
    받은 바이트를 다루는 규약은 하나다.

    형식은 **바이트를 보고 판정한다.** 확장자와 `Content-Type` 은 보내는 쪽이
    자유롭게 적을 수 있어, 그 말을 믿으면 `image/png` 라고 적힌 아무 파일이나
    저장된다.
    """
    viewer = "trainer" if sender == "trainer" else "member"
    text = message.strip()

    # 재시도는 기존 메시지를 바로 돌려줘 파일을 다시 쓰지 않는다(PDF 와 같은 규약).
    if client_request_id:
        existing = trainer_service.find_message_by_client_request(
            db, trainer_id, member_id, sender, client_request_id
        )
        if existing is not None:
            if existing.body != text or existing.attachment_type != "image":
                raise HTTPException(
                    status_code=409,
                    detail="같은 client_request_id에 다른 메시지를 보낼 수 없습니다.",
                )
            return trainer_service.chat_message_out(existing, viewer)

    settings = get_settings()
    data = await image.read(settings.max_chat_image_bytes + 1)
    if len(data) > settings.max_chat_image_bytes:
        raise HTTPException(status_code=413, detail="이미지 용량이 너무 큽니다.")
    try:
        chat_image_storage.sniff(data)
    except chat_image_storage.UnsupportedImage as exc:
        raise HTTPException(status_code=415, detail=str(exc)) from exc

    display_name = re.sub(
        r"[\x00-\x1f]", "_", PurePath(image.filename or "photo").name
    ) or "photo"
    # DB 컬럼 길이를 넘는 사용자 filename이 메시지 저장을 깨지 않게 한다.
    if len(display_name) > 255:
        display_name = display_name[:255]

    file_id: str | None = None
    try:
        file_id, _, _ = chat_image_storage.save(data)
        sent = trainer_service.send_message(
            db,
            trainer_id,
            member_id,
            sender,
            text,
            viewer=viewer,
            notify=notify,
            client_request_id=client_request_id,
            attachment_type="image",
            attachment_file_name=display_name,
            attachment_file_id=file_id,
            attachment_file_size=len(data),
        )
        # 동시 재시도 두 건이 모두 사전 조회를 통과할 수 있다. DB 멱등키에서
        # 진 요청이 기존 메시지를 반환했다면, 그 요청이 쓴 여분 파일을 지운다.
        if sent.attachment is None or sent.attachment.file_id != file_id:
            chat_image_storage.delete(file_id)
        return sent
    except trainer_service.IdempotencyConflict as exc:
        if file_id:
            chat_image_storage.delete(file_id)
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except chat_image_storage.ImageStorageError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    except Exception:
        # DB/notification 저장이 완료되지 않았다면 고립 파일을 남기지 않는다.
        if file_id:
            db.rollback()
            persisted = db.scalar(
                select(ChatMessage.id).where(
                    ChatMessage.attachment_file_id == file_id
                )
            )
            if persisted is None:
                chat_image_storage.delete(file_id)
        raise
