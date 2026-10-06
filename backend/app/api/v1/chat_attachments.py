"""Authenticated access to the file carried by a chat message.

주간 리포트 PDF(#778)로 시작해 코칭 사진(#921)이 더해졌다. 두 종류가 한 경로를
쓰는 이유는 **권한 판단이 같기 때문이다** — 그 스레드의 두 사람만 볼 수 있다.
경로를 나누면 그 판단이 두 벌이 되고, 한쪽만 고쳐지는 날이 온다.

사진을 **받아 저장하는** 규약도 여기 둔다([receive_chat_image]). 트레이너가
보내는 사진(#921)과 회원이 보내는 사진(#1665)은 보내는 사람만 다르고 형식 판정·
용량 상한·멱등 처리·고립 파일 정리가 모두 같다. 두 벌로 두면 한쪽만 느슨해진다.
"""
from __future__ import annotations

import logging
import re
from pathlib import PurePath
from urllib.parse import quote
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Request, UploadFile
from sqlalchemy import select
from sqlalchemy.orm import Session
from starlette.responses import StreamingResponse

from app.api.deps import RequireUser, ensure_consented
from app.core.config import get_settings
from app.db.session import get_db
from app.models.models import ChatMessage, TrainerClient
from app.schemas.trainer_api import ChatMessageOut
from app.services import (
    attachment_store,
    chat_image_storage,
    data_consent_service,
    report_pdf_storage,
)
from app.services.trainer import chat as trainer_chat_service
from app.services.trainer import _common as trainer_common_service

router = APIRouter(tags=["chat-attachments"])
logger = logging.getLogger(__name__)

#: 어느 종류든 "찾을 수 없어요" 로 끝난다. 권한이 없는 사람에게 파일의
#: 존재 여부를 알려 주지 않기 위해서다.
_NOT_FOUND = "첨부를 찾을 수 없어요."


@router.get("/chat/attachments/{file_id}")
def download_chat_attachment(
    file_id: str,
    request: Request,
    user: RequireUser,
    db: Annotated[Session, Depends(get_db)],
) -> StreamingResponse:
    # 회원·트레이너가 함께 쓰는 경로라 역할 의존성 대신 `RequireUser` 로 받는다.
    # 그래도 필수 동의 확인은 거친다(#3239) — 동의가 남은 트레이너가 회원 사진·
    # 리포트 PDF 를 받으면 안 된다(#3155). 파일을 찾기 전에 막아, 동의가 남은
    # 계정에는 file id 가 있는지도 드러나지 않는다.
    ensure_consented(request, user, db)
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
            blob, media_type = chat_image_storage.open_image(file_id)
        except FileNotFoundError as exc:
            raise HTTPException(status_code=404, detail=_NOT_FOUND) from exc
        except attachment_store.StoreError as exc:
            raise _store_unavailable() from exc
        # 사진은 대화 안에서 그려야 한다 — `attachment` 로 주면 브라우저가
        # 내려받기로 처리해 스레드에 아무것도 보이지 않는다.
        return _stream(
            blob,
            media_type=media_type,
            filename=message.attachment_file_name or "photo",
            disposition="inline",
        )

    try:
        blob = report_pdf_storage.open_pdf(file_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=_NOT_FOUND) from exc
    except attachment_store.StoreError as exc:
        raise _store_unavailable() from exc
    return _stream(
        blob,
        media_type="application/pdf",
        filename=message.attachment_file_name or "weekly-report.pdf",
        disposition="attachment",
    )


def _store_unavailable() -> HTTPException:
    """저장소 장애. 파일이 없다는 404 와 구분해야 앱이 다시 시도할 수 있다."""
    logger.exception("첨부 저장소를 읽지 못했습니다.")
    return HTTPException(
        status_code=503, detail="첨부를 잠시 불러올 수 없어요. 다시 시도해 주세요."
    )


def _content_disposition(disposition: str, filename: str) -> str:
    """`FileResponse` 와 같은 규칙의 Content-Disposition.

    ASCII 로 그대로 적을 수 있으면 `filename="…"`, 아니면 RFC 5987 의
    `filename*=utf-8''…` 로 적는다 — 한글 파일명이 깨지지 않게.
    """
    quoted = quote(filename)
    if quoted != filename:
        return f"{disposition}; filename*=utf-8''{quoted}"
    return f'{disposition}; filename="{filename}"'


def _stream(
    blob: attachment_store.OpenedBlob,
    *,
    media_type: str,
    filename: str,
    disposition: Literal["inline", "attachment"],
) -> StreamingResponse:
    """권한 확인이 끝난 첨부를 서버가 흘려보낸다. (#2817)

    저장소가 S3 여도 서명 URL 을 내주지 않는다 — 링크가 새면 권한 확인 없이
    열리고, 동의 철회(#1631)·담당 해제 뒤에도 만료 전까지 열린다. 바이트가
    서버를 거치는 비용보다 그 판단을 한 곳에 두는 쪽이 중요하다.
    """
    headers = {
        "Content-Disposition": _content_disposition(disposition, filename),
        # 사용자가 올린 바이트다. 브라우저가 형식을 다시 추측하지 않게 한다.
        "X-Content-Type-Options": "nosniff",
        # 권한이 바뀌면 바로 막혀야 하므로 중간 캐시에 남기지 않는다.
        "Cache-Control": "private, no-store",
    }
    if blob.size is not None:
        headers["Content-Length"] = str(blob.size)
    return StreamingResponse(blob.iter_chunks(), media_type=media_type, headers=headers)


def receive_chat_image(
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

    **동기 함수다(#2835).** DB 조회·커밋, 파일 저장(`os.fsync`)이 모두 동기라
    이벤트 루프에서 돌면 그동안 같은 프로세스의 다른 요청(헬스체크 포함)이 멈춘다.
    호출하는 라우트도 `def` 로 두어 FastAPI 스레드풀에서 돌게 하고, 업로드는
    `UploadFile.file` 을 동기로 읽는다.
    """
    viewer = "trainer" if sender == "trainer" else "member"
    text = message.strip()

    # 재시도는 기존 메시지를 바로 돌려줘 파일을 다시 쓰지 않는다(PDF 와 같은 규약).
    if client_request_id:
        existing = trainer_chat_service.find_message_by_client_request(
            db, trainer_id, member_id, sender, client_request_id
        )
        if existing is not None:
            if existing.body != text or existing.attachment_type != "image":
                raise HTTPException(
                    status_code=409,
                    detail="같은 client_request_id에 다른 메시지를 보낼 수 없어요.",
                )
            return trainer_chat_service.chat_message_out(existing, viewer)

    settings = get_settings()
    data = image.file.read(settings.max_chat_image_bytes + 1)
    if len(data) > settings.max_chat_image_bytes:
        raise HTTPException(status_code=413, detail="이미지 용량이 너무 커요.")
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
        # 저장 전에 회전 적용·메타데이터(EXIF 위치 등) 제거·재인코딩을 거친다
        # (#2829). 동기 핸들러라 이미 스레드풀에서 돌므로 이벤트 루프를 막지 않는다.
        # 디코딩할 수 없는 파일은 저장하지 않고 415 다.
        try:
            stored = chat_image_storage.save(data)
        except chat_image_storage.UnsupportedImage as exc:
            raise HTTPException(status_code=415, detail=str(exc)) from exc
        file_id = stored.file_id
        sent = trainer_chat_service.send_message(
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
            # 상대가 내려받는 것은 정리한 파일이다 — 크기도 그 값이다.
            attachment_file_size=stored.size,
        )
        # 동시 재시도 두 건이 모두 사전 조회를 통과할 수 있다. DB 멱등키에서
        # 진 요청이 기존 메시지를 반환했다면, 그 요청이 쓴 여분 파일을 지운다.
        if sent.attachment is None or sent.attachment.file_id != file_id:
            chat_image_storage.delete(file_id)
        return sent
    except trainer_common_service.IdempotencyConflict as exc:
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
