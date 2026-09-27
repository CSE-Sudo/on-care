"""Authenticated access to the file carried by a chat message.

주간 리포트 PDF(#778)로 시작해 코칭 사진(#921)이 더해졌다. 두 종류가 한 경로를
쓰는 이유는 **권한 판단이 같기 때문이다** — 그 스레드의 두 사람만 볼 수 있다.
경로를 나누면 그 판단이 두 벌이 되고, 한쪽만 고쳐지는 날이 온다.
"""
from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session
from starlette.responses import FileResponse

from app.api.deps import RequireUser
from app.db.session import get_db
from app.models.models import ChatMessage, TrainerClient
from app.services import (
    chat_image_storage,
    data_consent_service,
    report_pdf_storage,
)

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
                # 동의가 철회된 뒤 새 동의 없는 링크는 열람하지 않는다(#1631).
                data_consent_service.allows_access_clause(),
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
