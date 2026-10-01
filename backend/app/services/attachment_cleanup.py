"""탈퇴할 때 채팅 첨부 파일을 함께 지운다. (#2817)

`chat_messages` 행은 회원·트레이너 어느 쪽이 탈퇴해도 `users.id` CASCADE 로 그
스레드 전체가 사라진다. 그런데 첨부의 **바이트는 DB 밖**(로컬 디스크·S3)에 있어
CASCADE 가 닿지 않는다. 예전에는 그 바이트가 그대로 남아, 아무도 열 수 없는 건강
관련 사진·리포트가 서버에 쌓였다 — 처리방침의 "탈퇴 시 지체 없이 파기" 와 어긋난다.

**무엇을 지우는가 — 보존 기준.** 첨부 파일은 그 메시지 행과 수명이 같다. 탈퇴로
CASCADE 되는 메시지의 첨부만 지운다.

- 회원 탈퇴: 그 회원의 모든 스레드. 회원이 올린 사진과, 트레이너가 회원에게 보낸
  리포트·사진. 처리방침상 회원에게 전송된 리포트는 "회원의 기록" 이라 회원의 보관
  기간을 따른다 — 회원이 떠나면 함께 파기한다.
- 트레이너 탈퇴: 그 트레이너의 모든 스레드. 행이 CASCADE 로 사라지므로 남겨 둔
  파일은 누구도 열 수 없는 고아가 된다. 열람 경로가 없는 사본을 남기는 것은
  보존이 아니라 파기 누락이다.

**지우는 시점은 커밋 뒤다.** 커밋 전에 지우면 탈퇴가 실패해 롤백됐을 때 메시지는
남고 파일만 사라진다. 커밋 뒤에 파일 삭제가 실패하면 고아 파일이 남지만, 그건
로그로 남겨 다시 지울 수 있다 — 반대 방향(행만 남은 깨진 첨부)보다 낫다.
"""
from __future__ import annotations

import logging
from collections.abc import Iterable
from dataclasses import dataclass

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.models.models import ChatMessage
from app.services import chat_image_storage, report_pdf_storage

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class AttachmentFile:
    kind: str  # "image" | "pdf"
    file_id: str


def files_in_threads(
    db: Session,
    *,
    member_id: str | None = None,
    trainer_id: str | None = None,
) -> list[AttachmentFile]:
    """[member_id] 또는 [trainer_id] 가 낀 스레드의 첨부 파일 목록.

    탈퇴 요청이 계정 행을 지우기 **전에** 부른다 — 지운 뒤에는 CASCADE 로 행이
    사라져 무엇을 지울지 알 수 없다.
    """
    conditions = []
    if member_id is not None:
        conditions.append(ChatMessage.member_id == member_id)
    if trainer_id is not None:
        conditions.append(ChatMessage.trainer_id == trainer_id)
    if not conditions:
        return []
    rows = db.execute(
        select(ChatMessage.attachment_type, ChatMessage.attachment_file_id)
        .where(
            or_(*conditions),
            ChatMessage.attachment_file_id.is_not(None),
            ChatMessage.attachment_type.in_(("image", "pdf")),
        )
        .order_by(ChatMessage.attachment_file_id)
    ).all()
    return [AttachmentFile(kind=kind, file_id=file_id) for kind, file_id in rows]


def purge(files: Iterable[AttachmentFile]) -> int:
    """파일을 저장소에서 지운다. 지운(또는 이미 없던) 수를 돌려준다.

    하나가 실패해도 나머지는 계속 지운다. 실패는 file_id 와 함께 경고로 남긴다 —
    탈퇴 응답을 실패로 돌리면 계정은 이미 지워졌는데 앱은 실패로 읽는다.
    """
    done = 0
    for file in files:
        try:
            if file.kind == "image":
                chat_image_storage.delete(file.file_id)
            else:
                report_pdf_storage.delete(file.file_id)
        except Exception:  # noqa: BLE001 — 한 파일 때문에 나머지를 남기지 않는다.
            logger.warning(
                "탈퇴 첨부 삭제 실패 — 수동 정리 필요: kind=%s file_id=%s",
                file.kind,
                file.file_id,
                exc_info=True,
            )
            continue
        done += 1
    return done
