"""#778 주간 리포트 PDF의 최소 로컬 파일 저장소."""
from __future__ import annotations

import os
import re
import uuid
from pathlib import Path

from app.core.config import get_settings

_FILE_ID = re.compile(r"^[0-9a-f]{32}$")


class PdfStorageError(Exception):
    pass


def _root() -> Path:
    root = Path(get_settings().report_pdf_storage_dir).resolve()
    root.mkdir(parents=True, exist_ok=True)
    return root


def save(data: bytes, *, file_id: str | None = None) -> str:
    """UUID identifier로 원자적으로 저장한다. 사용자 filename은 경로에 쓰지 않는다.

    [file_id] 를 주면 그 이름으로 덮어쓴다 — 서버가 뜰 때마다 같은 파일을 다시
    쓰는 데모 시드용이다(#2788).
    """
    if file_id is None:
        file_id = uuid.uuid4().hex
    elif not _FILE_ID.fullmatch(file_id):
        raise PdfStorageError("PDF 식별자가 올바르지 않습니다.")
    root = _root()
    final_path = root / f"{file_id}.pdf"
    temporary_path = root / f".{file_id}.tmp"
    try:
        with temporary_path.open("xb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        temporary_path.replace(final_path)
    except OSError as exc:
        temporary_path.unlink(missing_ok=True)
        raise PdfStorageError("리포트 PDF를 저장하지 못했습니다.") from exc
    return file_id


def path_for(file_id: str) -> Path:
    """DB identifier만 받아 path traversal 없이 실제 경로를 돌려준다."""
    if not _FILE_ID.fullmatch(file_id):
        raise FileNotFoundError(file_id)
    path = _root() / f"{file_id}.pdf"
    if not path.is_file():
        raise FileNotFoundError(file_id)
    return path


def delete(file_id: str) -> None:
    if _FILE_ID.fullmatch(file_id):
        (_root() / f"{file_id}.pdf").unlink(missing_ok=True)
