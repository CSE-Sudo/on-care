"""사진 정리 함수 — 회전 적용·메타데이터 제거·해상도 상한. (#2829)

DB 없이 도는 단위 테스트다. 채팅 사진(`sanitize`, 원본 형식 유지)과 끼니 사진
(`to_jpeg`)이 같은 규칙을 쓰는지, 그리고 그 규칙이 촬영 위치·기기 정보를 남기지
않는지 본다.
"""
from __future__ import annotations

import io

import pytest
from PIL import Image, PngImagePlugin

from app.services import chat_image_storage, diet_photo_service, image_sanitize

GPS_TAG = 0x8825
ORIENTATION_TAG = 0x0112
MAKE_TAG = 0x010F


def _exif(*, orientation: int | None = None) -> Image.Exif:
    exif = Image.Exif()
    exif[GPS_TAG] = {1: "N", 2: (37.0, 33.0, 59.0), 3: "E", 4: (126.0, 58.0, 41.0)}
    exif[MAKE_TAG] = "PhoneMaker"
    if orientation is not None:
        exif[ORIENTATION_TAG] = orientation
    return exif


def _jpeg(size=(300, 200), **kwargs) -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", size, (200, 30, 30)).save(buffer, format="JPEG", **kwargs)
    return buffer.getvalue()


def _open(data: bytes) -> Image.Image:
    image = Image.open(io.BytesIO(data))
    image.load()
    return image


# ---- 메타데이터 ----


def test_gps_and_device_exif_are_dropped_from_a_jpeg():
    clean = image_sanitize.sanitize(_jpeg(exif=_exif()))

    stored = _open(clean.data)
    assert stored.format == "JPEG"
    assert not dict(stored.getexif())
    assert b"PhoneMaker" not in clean.data
    assert (clean.extension, clean.media_type) == ("jpg", "image/jpeg")


def test_xmp_is_dropped():
    xmp = b'<x:xmpmeta xmlns:x="adobe:ns:meta/">home-address</x:xmpmeta>'
    clean = image_sanitize.sanitize(_jpeg(xmp=xmp))

    assert b"home-address" not in clean.data
    assert "xmp" not in _open(clean.data).info


def test_png_text_chunks_are_dropped():
    info = PngImagePlugin.PngInfo()
    info.add_text("Location", "37.5665,126.9780")
    buffer = io.BytesIO()
    Image.new("RGB", (8, 8), (1, 2, 3)).save(buffer, format="PNG", pnginfo=info)

    clean = image_sanitize.sanitize(buffer.getvalue())

    assert b"37.5665" not in clean.data
    assert "Location" not in _open(clean.data).info


def test_webp_exif_is_dropped():
    buffer = io.BytesIO()
    Image.new("RGB", (16, 16), (9, 9, 9)).save(
        buffer, format="WEBP", exif=_exif()
    )

    clean = image_sanitize.sanitize(buffer.getvalue())

    assert (clean.extension, clean.media_type) == ("webp", "image/webp")
    assert not dict(_open(clean.data).getexif())


def test_the_color_profile_is_kept():
    """ICC 는 개인 정보가 아니라 색 값이다 — 결과지 사진 색이 탁해지지 않게 남긴다."""
    from PIL import ImageCms

    icc = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    clean = image_sanitize.sanitize(_jpeg(icc_profile=icc, exif=_exif()))

    stored = _open(clean.data)
    assert stored.info.get("icc_profile") == icc
    assert not dict(stored.getexif())


# ---- 회전 ----


@pytest.mark.parametrize("orientation", [6, 8])
def test_a_portrait_photo_stays_portrait_after_the_tag_is_dropped(orientation):
    """가로로 저장되고 회전 태그로 세로를 말하는 휴대폰 사진."""
    clean = image_sanitize.sanitize(
        _jpeg(size=(300, 200), exif=_exif(orientation=orientation))
    )

    stored = _open(clean.data)
    assert stored.size == (200, 300)
    assert ORIENTATION_TAG not in stored.getexif()


# ---- 형식·투명도 ----


def test_png_transparency_is_kept():
    buffer = io.BytesIO()
    image = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
    image.putpixel((5, 5), (255, 0, 0, 255))
    image.save(buffer, format="PNG")

    clean = image_sanitize.sanitize(buffer.getvalue())

    stored = _open(clean.data)
    assert stored.format == "PNG"
    assert stored.mode == "RGBA"
    assert stored.getpixel((0, 0))[3] == 0
    assert stored.getpixel((5, 5)) == (255, 0, 0, 255)


def test_palette_png_transparency_is_kept():
    buffer = io.BytesIO()
    Image.new("P", (4, 4), 0).save(buffer, format="PNG", transparency=0)

    stored = _open(image_sanitize.sanitize(buffer.getvalue()).data)

    assert stored.convert("RGBA").getpixel((0, 0))[3] == 0


def test_the_original_format_is_kept():
    for fmt, extension in (("JPEG", "jpg"), ("PNG", "png"), ("WEBP", "webp")):
        buffer = io.BytesIO()
        Image.new("RGB", (6, 6), (5, 5, 5)).save(buffer, format=fmt)
        clean = image_sanitize.sanitize(buffer.getvalue())
        assert clean.extension == extension, fmt
        assert _open(clean.data).format == fmt


# ---- 해상도 ----


def test_the_long_edge_is_capped():
    clean = image_sanitize.sanitize(_jpeg(size=(4096, 1024)))

    assert max(clean.width, clean.height) == image_sanitize.CHAT_MAX_EDGE
    assert (clean.width, clean.height) == (2048, 512)


def test_a_small_photo_keeps_its_size():
    clean = image_sanitize.sanitize(_jpeg(size=(640, 480)))

    assert (clean.width, clean.height) == (640, 480)


# ---- 읽을 수 없는 파일 ----


@pytest.mark.parametrize(
    "data",
    [
        b"\xff\xd8\xff\xe0" + b"\x00" * 32,  # 매직 넘버만 맞춘 JPEG
        b"\x89PNG\r\n\x1a\n" + b"0" * 32,  # 매직 넘버만 맞춘 PNG
        b"RIFF\x00\x00\x00\x00WEBPVP8 " + b"\x00" * 16,  # 매직 넘버만 맞춘 WebP
        b"not an image",
    ],
    ids=["jpeg-magic", "png-magic", "webp-magic", "text"],
)
def test_undecodable_bytes_are_refused(data):
    with pytest.raises(image_sanitize.UndecodableImage):
        image_sanitize.sanitize(data)


def test_a_truncated_photo_is_refused():
    with pytest.raises(image_sanitize.UndecodableImage):
        image_sanitize.sanitize(_jpeg(size=(400, 400))[:300])


def test_a_format_we_do_not_take_is_refused():
    buffer = io.BytesIO()
    Image.new("RGB", (4, 4)).save(buffer, format="GIF")

    with pytest.raises(image_sanitize.UndecodableImage):
        image_sanitize.sanitize(buffer.getvalue())


# ---- 저장소 연결 ----


def test_storage_save_writes_the_cleaned_bytes(tmp_path, monkeypatch):
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "chat_image_storage_dir", str(tmp_path))

    stored = chat_image_storage.save(_jpeg(exif=_exif()))

    opened, media_type = chat_image_storage.open_image(stored.file_id)
    written = opened.read_all()
    assert media_type == "image/jpeg"
    assert stored.size == len(written)
    assert not dict(_open(written).getexif())


def test_storage_save_refuses_undecodable_bytes(tmp_path, monkeypatch):
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "chat_image_storage_dir", str(tmp_path))

    with pytest.raises(chat_image_storage.UnsupportedImage):
        chat_image_storage.save(b"\xff\xd8\xff\xe0" + b"\x00" * 32)
    # 아무것도 남기지 않는다.
    assert not [p for p in tmp_path.iterdir() if p.is_file()]


def test_seed_assets_can_skip_cleaning(tmp_path, monkeypatch):
    """번들 데모 자산은 앱 번들과 바이트가 같아야 한다(#2788)."""
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "chat_image_storage_dir", str(tmp_path))
    original = _jpeg()

    stored = chat_image_storage.save(
        original, file_id="0" * 32, sanitize=False
    )

    opened, _ = chat_image_storage.open_image(stored.file_id)
    assert opened.read_all() == original


# ---- 끼니 사진과 같은 함수 ----


def test_diet_photos_use_the_same_cleaning_function(monkeypatch):
    calls: list[int] = []
    real = image_sanitize._open_upright

    def spy(data, max_edge):
        calls.append(max_edge)
        return real(data, max_edge)

    monkeypatch.setattr(image_sanitize, "_open_upright", spy)

    diet_photo_service._downscale_to_jpeg(_jpeg(exif=_exif()))
    image_sanitize.sanitize(_jpeg(exif=_exif()))

    assert calls == [1024, image_sanitize.CHAT_MAX_EDGE]


def test_diet_photo_still_drops_location_and_applies_rotation():
    data, width, height = diet_photo_service._downscale_to_jpeg(
        _jpeg(size=(300, 200), exif=_exif(orientation=6))
    )

    assert (width, height) == (200, 300)
    assert not dict(_open(data).getexif())
