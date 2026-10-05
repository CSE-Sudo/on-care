"""#778 주간 리포트 PDF의 저장 규약.

바이트를 어디에 두는지(로컬 디스크·S3)는 `attachment_store` 가 정한다(#2817).
여기는 식별자 규약만 진다 — 사용자 filename 은 경로·키에 쓰지 않는다.
"""
from __future__ import annotations

import re
import uuid

from app.services import attachment_store

_FILE_ID = re.compile(r"^[0-9a-f]{32}$")
_MEDIA_TYPE = "application/pdf"


class PdfStorageError(Exception):
    pass


def _store() -> attachment_store.BlobStore:
    return attachment_store.get_store("report-pdfs")


def save(data: bytes, *, file_id: str | None = None) -> str:
    """UUID identifier로 저장한다. 사용자 filename은 경로에 쓰지 않는다.

    [file_id] 를 주면 그 이름으로 덮어쓴다 — 서버가 뜰 때마다 같은 파일을 다시
    쓰는 데모 시드용이다(#2788).
    """
    if file_id is None:
        file_id = uuid.uuid4().hex
    elif not _FILE_ID.fullmatch(file_id):
        raise PdfStorageError("PDF 식별자가 올바르지 않습니다.")
    try:
        _store().put(f"{file_id}.pdf", data, content_type=_MEDIA_TYPE)
    except OSError as exc:
        raise PdfStorageError("리포트 PDF를 저장하지 못했습니다.") from exc
    return file_id


def open_pdf(file_id: str) -> attachment_store.OpenedBlob:
    """DB identifier만 받아 path traversal 없이 연다. 없으면 FileNotFoundError."""
    if not _FILE_ID.fullmatch(file_id):
        raise FileNotFoundError(file_id)
    return _store().open(f"{file_id}.pdf")


def delete(file_id: str) -> None:
    """[file_id] 의 PDF 를 지운다. 없으면 조용히 끝난다. 저장소 장애는 OSError."""
    if _FILE_ID.fullmatch(file_id):
        _store().delete(f"{file_id}.pdf")
