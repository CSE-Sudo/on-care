"""채팅 이미지 첨부의 로컬 파일 저장소. (#921)

리포트 PDF 저장소(`report_pdf_storage`)와 같은 규약을 따른다 — 사용자 파일명은
경로에 쓰지 않고, UUID 로 저장하고, 읽을 때는 DB 가 준 식별자만 받는다. 사용자
문자열이 경로에 닿는 순간 `../` 하나로 서버의 아무 파일이나 내려받게 된다.

PDF 와 자리를 나눈 이유는 지우는 주기가 다르기 때문이다. 리포트 PDF 는 그 주의
산출물이고, 코칭 사진은 대화의 일부로 남는다.

형식은 **서버가 바이트를 보고 정한다.** 확장자나 `Content-Type` 은 보내는 쪽이
자유롭게 적을 수 있어, 그 말을 믿으면 `.png` 라고 적힌 아무 파일이나 저장된다.
"""
from __future__ import annotations

import os
import re
import uuid
from pathlib import Path

from app.core.config import get_settings

_FILE_ID = re.compile(r"^[0-9a-f]{32}$")

#: 매직 넘버 → (확장자, media type). 이 셋만 받는다 — 브라우저가 어디서나 그릴
#: 수 있고, 스크립트를 품을 수 있는 형식(SVG 등)은 넣지 않는다.
_SIGNATURES: tuple[tuple[bytes, str, str], ...] = (
    (b"\xff\xd8\xff", "jpg", "image/jpeg"),
    (b"\x89PNG\r\n\x1a\n", "png", "image/png"),
)

#: WebP 는 `RIFF....WEBP` 라 접두사 하나로 못 잡는다.
_WEBP_PREFIX = b"RIFF"
_WEBP_TAG = b"WEBP"


class ImageStorageError(Exception):
    """저장에 실패했다."""


class UnsupportedImage(Exception):
    """바이트가 우리가 받는 이미지 형식이 아니다."""


def _root() -> Path:
    root = Path(get_settings().chat_image_storage_dir).resolve()
    root.mkdir(parents=True, exist_ok=True)
    return root


def sniff(data: bytes) -> tuple[str, str]:
    """바이트로 형식을 판정해 (확장자, media type) 을 돌려준다.

    보내는 쪽이 적어 준 `Content-Type` 은 참고하지 않는다 — 그 말을 믿으면
    `image/png` 라고 적힌 실행 파일이 그대로 저장된다.
    """
    for signature, extension, media_type in _SIGNATURES:
        if data.startswith(signature):
            return extension, media_type
    if data[:4] == _WEBP_PREFIX and data[8:12] == _WEBP_TAG:
        return "webp", "image/webp"
    raise UnsupportedImage("JPG·PNG·WebP 이미지만 보낼 수 있습니다.")


def save(data: bytes, *, file_id: str | None = None) -> tuple[str, str, str]:
    """이미지를 저장하고 (file_id, 확장자, media type) 을 돌려준다.

    [file_id] 를 주면 그 이름으로 덮어쓴다 — 서버가 뜰 때마다 같은 파일을 다시
    쓰는 데모 시드용이다(#2788). 주지 않으면 새 UUID 다.
    """
    extension, media_type = sniff(data)
    if file_id is None:
        file_id = uuid.uuid4().hex
    elif not _FILE_ID.fullmatch(file_id):
        raise ImageStorageError("이미지 식별자가 올바르지 않습니다.")
    root = _root()
    final_path = root / f"{file_id}.{extension}"
    temporary_path = root / f".{file_id}.tmp"
    try:
        with temporary_path.open("xb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        temporary_path.replace(final_path)
    except OSError as exc:
        temporary_path.unlink(missing_ok=True)
        raise ImageStorageError("이미지를 저장하지 못했습니다.") from exc
    return file_id, extension, media_type


def path_for(file_id: str) -> tuple[Path, str]:
    """DB 식별자만 받아 (경로, media type) 을 돌려준다.

    확장자는 저장할 때 서버가 정한 것이라 여기서 다시 찾는다 — 응답에
    media type 을 실어야 브라우저가 내려받기 대신 그림으로 그린다.
    """
    if not _FILE_ID.fullmatch(file_id):
        raise FileNotFoundError(file_id)
    root = _root()
    for _, extension, media_type in _SIGNATURES:
        path = root / f"{file_id}.{extension}"
        if path.is_file():
            return path, media_type
    path = root / f"{file_id}.webp"
    if path.is_file():
        return path, "image/webp"
    raise FileNotFoundError(file_id)


def delete(file_id: str) -> None:
    if not _FILE_ID.fullmatch(file_id):
        return
    root = _root()
    for extension in ("jpg", "png", "webp"):
        (root / f"{file_id}.{extension}").unlink(missing_ok=True)
