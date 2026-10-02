"""끼니 사진 저장·조회 (#699).

`POST /diet/analyze` 가 받은 사진은 인식에만 쓰이고 버려졌다. 그래서 회원 앱의
끼니 사진은 번들 자산을 가리키는 데모 값뿐이었고, 트레이너는 회원이 무엇을
먹었는지 **글자로만** 볼 수 있었다. 여기서 사진을 축소해 공유 DB 에 남긴다.

원본이 아니라 축소본을 두는 이유는 용량이다. 끼니마다 사진이면 회원 한 명이
하루 서너 장이고, 요즘 휴대폰 사진은 한 장에 3~5MB 다. 장변을 [_MAX_EDGE] 로
줄이고 JPEG 로 다시 인코딩하면 한 장이 대략 100~200KB 로 떨어진다 — 화면에
띄우는 카드 크기에는 충분하고, 행 크기는 예측 가능해진다.

재인코딩은 덤으로 메타데이터도 털어 낸다. 휴대폰 사진의 EXIF 에는 촬영 위치가
들어 있을 수 있는데, 끼니 사진을 트레이너와 공유하는 것이 **집 좌표**를 공유하는
뜻이 되어서는 안 된다. 회전 정보만 픽셀에 적용하고 나머지는 버린다.

정리 규칙은 채팅 사진과 같은 `image_sanitize` 한 곳에 있다(#2829).
"""
from __future__ import annotations

import logging
import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.models import DietPhoto
from app.services import image_sanitize

logger = logging.getLogger(__name__)

# 저장 축소본의 장변 상한(px). 회원 앱 끼니 카드와 트레이너 웹 썸네일 모두
# 이보다 훨씬 작게 그린다.
_MAX_EDGE = 1024
_JPEG_QUALITY = 82


def _downscale_to_jpeg(image_bytes: bytes) -> tuple[bytes, int, int] | None:
    """축소·재인코딩한 JPEG 과 크기를 돌려준다. 읽을 수 없으면 None."""
    try:
        clean = image_sanitize.to_jpeg(
            image_bytes, max_edge=_MAX_EDGE, quality=_JPEG_QUALITY
        )
    except image_sanitize.UndecodableImage:
        # 손상된 업로드는 여기서 끝난다 — 끼니 기록은 사진 없이 남는다.
        logger.warning("끼니 사진을 읽지 못했습니다 — 사진 없이 저장합니다.", exc_info=True)
        return None
    return clean.data, clean.width, clean.height


def store_for_entry(
    db: Session, user_id: str, entry_id: str, image_bytes: bytes
) -> DietPhoto | None:
    """끼니에 사진을 붙인다. 저장하지 못하면 None.

    **사진 실패가 끼니 기록을 실패시키지 않는다.** 인식과 저장은 이미 끝난 뒤라,
    여기서 예외를 올리면 사용자는 "분석에 실패했다" 는 화면을 보고 다시 찍는데
    기록은 이미 들어가 있어 같은 끼니가 두 번 남는다.

    업로드 크기 자체는 본문 크기 미들웨어(`max_upload_bytes`)가 이미 413 으로
    막는다. 여기서 다시 세지 않고, 읽을 수 없는 바이트만 걸러낸다.
    """
    if not image_bytes:
        return None

    downscaled = _downscale_to_jpeg(image_bytes)
    if downscaled is None:
        return None
    data, width, height = downscaled

    photo = DietPhoto(
        id=f"dietpic-{uuid.uuid4().hex[:16]}",
        entry_id=entry_id,
        user_id=user_id,
        content_type="image/jpeg",
        width=width,
        height=height,
        byte_size=len(data),
        data=data,
    )
    db.add(photo)
    try:
        db.commit()
    except Exception:  # noqa: BLE001
        db.rollback()
        logger.warning("끼니 사진 저장 실패 (entry=%s)", entry_id, exc_info=True)
        return None
    return photo


def photo_ids_for_entries(db: Session, entry_ids: list[str]) -> dict[str, str]:
    """{entry_id: photo_id} — 하루치 조회가 사진 바이트를 끌고 오지 않도록 id 만 읽는다."""
    if not entry_ids:
        return {}
    rows = db.execute(
        select(DietPhoto.entry_id, DietPhoto.id).where(DietPhoto.entry_id.in_(entry_ids))
    ).all()
    return {entry_id: photo_id for entry_id, photo_id in rows}


def get_owned_photo(db: Session, photo_id: str, user_id: str) -> DietPhoto | None:
    """이 회원의 사진. 남의 사진이면 None — id 를 찍어 맞혀도 열리지 않는다."""
    return db.scalar(
        select(DietPhoto).where(DietPhoto.id == photo_id, DietPhoto.user_id == user_id)
    )
