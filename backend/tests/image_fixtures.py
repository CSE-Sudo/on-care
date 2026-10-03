"""테스트용 진짜 이미지 바이트. (#3041)

`POST /diet/analyze` 는 인식 전에 사진을 픽셀까지 읽어 정리한다. 매직 넘버만 맞춘
가짜 바이트(`b"\\xff\\xd8\\xff\\xe0 ... fake"`)는 이제 415 로 끝나므로, 분석 흐름을
지나가야 하는 테스트는 여기 있는 작은 진짜 이미지를 쓴다.
"""
from __future__ import annotations

import io

from PIL import Image

#: EXIF 태그 번호.
ORIENTATION = 0x0112
MAKE = 0x010F
MODEL = 0x0110
DATETIME = 0x0132
GPS_IFD = 0x8825


def _encode(size, color, fmt: str, **options) -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", size, color).save(buffer, format=fmt, **options)
    return buffer.getvalue()


def jpeg_bytes(
    size: tuple[int, int] = (64, 48),
    color: tuple[int, int, int] = (200, 120, 60),
    *,
    exif: Image.Exif | None = None,
) -> bytes:
    options: dict[str, object] = {"quality": 85}
    if exif is not None:
        options["exif"] = exif
    return _encode(size, color, "JPEG", **options)


def png_bytes(
    size: tuple[int, int] = (64, 48), color: tuple[int, int, int] = (60, 160, 90)
) -> bytes:
    return _encode(size, color, "PNG")


def webp_bytes(
    size: tuple[int, int] = (64, 48), color: tuple[int, int, int] = (90, 60, 200)
) -> bytes:
    return _encode(size, color, "WEBP", quality=85)


def phone_exif(*, orientation: int | None = None) -> Image.Exif:
    """휴대폰 사진처럼 촬영 위치·시각·기기를 담은 EXIF."""
    exif = Image.Exif()
    exif[MAKE] = "TestPhone"
    exif[MODEL] = "TP-1"
    exif[DATETIME] = "2026:10:01 19:30:00"
    # GPS IFD: 위도 37°33'N, 경도 126°56'E(테스트 값).
    exif.get_ifd(GPS_IFD).update(
        {
            1: "N",
            2: (37.0, 33.0, 0.0),
            3: "E",
            4: (126.0, 56.0, 0.0),
        }
    )
    if orientation is not None:
        exif[ORIENTATION] = orientation
    return exif


#: 분석 흐름 테스트가 쓰는 기본 사진.
JPEG = jpeg_bytes()
PNG = png_bytes()
WEBP = webp_bytes()
