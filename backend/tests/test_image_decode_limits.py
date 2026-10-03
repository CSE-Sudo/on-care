"""업로드 사진을 펼치기 전에 크기를 본다. (#3040)

바이트 상한은 압축된 크기라 펼친 메모리를 막지 못한다. 단색에 가까운 PNG 는 수백 KB
로 1억 픽셀을 넘길 수 있다. `image_sanitize` 가

- 헤더의 장변·픽셀 수로 **디코딩 전에** 거절하는지,
- Pillow 의 폭탄 경고를 경고로 흘리지 않고 거절하는지(전역 설정은 건드리지 않고),
- JPEG 을 축소 디코딩해 큰 원본도 상한 안에서 처리하는지,
- 애니메이션의 프레임 수를 보는지

를 본다. DB 없이 도는 단위 테스트다. 상한은 설정을 작게 바꿔 작은 이미지로 확인한다
— 진짜 1억 픽셀 이미지를 테스트에서 만들 필요는 없다.
"""
from __future__ import annotations

import io
import warnings

import pytest
from PIL import Image, ImageFile

from app.core.config import get_settings
from app.services import diet_photo_service, image_sanitize


def _png(size, color=(30, 30, 30)) -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", size, color).save(buffer, format="PNG")
    return buffer.getvalue()


def _jpeg(size, color=(200, 30, 30)) -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", size, color).save(buffer, format="JPEG", quality=80)
    return buffer.getvalue()


def _animated_png(frames: int) -> bytes:
    images = [
        Image.new("RGB", (40, 30), (10 * i % 255, 200, 40)) for i in range(frames)
    ]
    buffer = io.BytesIO()
    images[0].save(
        buffer, format="PNG", save_all=True, append_images=images[1:], duration=50
    )
    return buffer.getvalue()


@pytest.fixture
def limits(monkeypatch):
    """상한을 바꿔 쓰는 도우미. 원래 값은 테스트가 끝나면 돌아온다."""
    settings = get_settings()

    def set_limits(*, pixels: int | None = None, edge: int | None = None) -> None:
        if pixels is not None:
            monkeypatch.setattr(settings, "max_image_decode_pixels", pixels)
        if edge is not None:
            monkeypatch.setattr(settings, "max_image_decode_edge", edge)

    return set_limits


@pytest.fixture
def load_calls(monkeypatch):
    """`ImageFile.load`(실제 디코딩) 호출 횟수."""
    calls: list[int] = []
    real = ImageFile.ImageFile.load

    def spy(self):
        calls.append(1)
        return real(self)

    monkeypatch.setattr(ImageFile.ImageFile, "load", spy)
    return calls


# ---- 기본값 ----


def test_defaults_are_set():
    settings = get_settings()
    assert settings.max_image_decode_pixels == 40_000_000
    assert settings.max_image_decode_edge == 12_000


def test_a_normal_photo_still_passes():
    clean = image_sanitize.sanitize(_jpeg((1600, 1200)))
    assert (clean.width, clean.height) == (1600, 1200)


# ---- 픽셀 수 ----


def test_a_photo_just_under_the_pixel_cap_passes(limits):
    limits(pixels=200 * 100)
    clean = image_sanitize.sanitize(_png((200, 100)))
    assert (clean.width, clean.height) == (200, 100)


def test_a_photo_over_the_pixel_cap_is_refused_before_decoding(limits, load_calls):
    limits(pixels=200 * 100 - 1)
    with pytest.raises(image_sanitize.UndecodableImage):
        image_sanitize.sanitize(_png((200, 100)))
    assert load_calls == []


def test_a_highly_compressible_png_is_refused(limits):
    """작은 파일이 큰 그림일 수 있다 — 바이트가 아니라 픽셀로 센다."""
    data = _png((3000, 3000), color=(0, 0, 0))
    assert len(data) < 200_000
    limits(pixels=1_000_000)
    with pytest.raises(image_sanitize.UndecodableImage):
        image_sanitize.sanitize(data)


def test_the_diet_path_uses_the_same_cap(limits):
    limits(pixels=10_000)
    with pytest.raises(image_sanitize.UndecodableImage):
        image_sanitize.to_jpeg(_png((200, 100)), max_edge=1024, quality=82)


def test_a_diet_photo_over_the_cap_is_dropped_without_raising(limits):
    """끼니 기록은 사진 없이 남는다 — 사진 실패가 기록을 실패시키지 않는다."""
    limits(pixels=10_000)
    assert diet_photo_service._downscale_to_jpeg(_png((200, 100))) is None


# ---- 장변 ----


def test_a_very_long_thin_image_is_refused(limits, load_calls):
    limits(edge=500)
    with pytest.raises(image_sanitize.UndecodableImage):
        image_sanitize.sanitize(_png((600, 4)))
    assert load_calls == []


def test_the_edge_cap_is_inclusive(limits):
    limits(edge=600)
    clean = image_sanitize.sanitize(_png((600, 4)))
    assert clean.width == 600


def test_check_dimensions_rejects_an_empty_size():
    with pytest.raises(image_sanitize.UndecodableImage):
        image_sanitize.check_dimensions(0, 10)


# ---- Pillow 폭탄 경고 ----


def test_the_pillow_bomb_warning_is_treated_as_a_refusal(monkeypatch):
    """기본 Pillow 는 상한의 두 배까지 경고만 내고 펼친다 — 그 구간도 거절한다."""
    monkeypatch.setattr(Image, "MAX_IMAGE_PIXELS", 1_000)
    # 40×40 = 1,600: Pillow 상한(1,000) 초과, 두 배(2,000) 미만 — 경고 구간.
    with pytest.raises(image_sanitize.UndecodableImage):
        image_sanitize.sanitize(_png((40, 40)))


def test_the_bomb_warning_filter_does_not_leak_out(monkeypatch):
    """경고를 예외로 바꾸는 것은 정리 호출 안에서만이다."""
    monkeypatch.setattr(Image, "MAX_IMAGE_PIXELS", 1_000)
    with pytest.raises(image_sanitize.UndecodableImage):
        image_sanitize.sanitize(_png((40, 40)))

    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        with Image.open(io.BytesIO(_png((40, 40)))) as opened:
            opened.load()
    assert any(
        issubclass(w.category, Image.DecompressionBombWarning) for w in caught
    )


def test_the_global_pillow_limit_is_left_alone():
    before = Image.MAX_IMAGE_PIXELS
    image_sanitize.sanitize(_jpeg((300, 200)))
    assert Image.MAX_IMAGE_PIXELS == before


# ---- JPEG 축소 디코딩 ----


def test_a_large_jpeg_is_decoded_at_a_reduced_scale(limits):
    """원본 3200×2400(768만)은 상한(200만)을 넘지만, 1/2 로 펼치면 192만이라 통과한다."""
    limits(pixels=2_000_000)
    clean = image_sanitize.sanitize(_jpeg((3200, 2400)), max_edge=1024)
    assert max(clean.width, clean.height) == 1024


def test_the_same_size_png_cannot_be_reduced_and_is_refused(limits):
    """PNG 는 축소 디코딩이 없다 — 같은 크기라도 상한에 그대로 걸린다."""
    limits(pixels=2_000_000)
    with pytest.raises(image_sanitize.UndecodableImage):
        image_sanitize.sanitize(_png((3200, 2400)), max_edge=1024)


def test_a_reduced_jpeg_keeps_its_rotation():
    exif = Image.Exif()
    exif[0x0112] = 6  # 90도 회전
    buffer = io.BytesIO()
    Image.new("RGB", (3000, 2000), (50, 60, 70)).save(
        buffer, format="JPEG", exif=exif
    )
    clean = image_sanitize.to_jpeg(buffer.getvalue(), max_edge=1024, quality=82)
    assert clean.width < clean.height
    assert max(clean.width, clean.height) == 1024


def test_a_small_jpeg_is_not_reduced():
    clean = image_sanitize.sanitize(_jpeg((640, 480)), max_edge=2048)
    assert (clean.width, clean.height) == (640, 480)


# ---- 애니메이션 ----


def test_an_animated_png_keeps_only_the_first_frame():
    clean = image_sanitize.sanitize(_animated_png(3))
    with Image.open(io.BytesIO(clean.data)) as stored:
        assert getattr(stored, "n_frames", 1) == 1
        assert stored.size == (40, 30)


def test_too_many_frames_are_refused(monkeypatch):
    monkeypatch.setattr(image_sanitize, "MAX_FRAMES", 2)
    with pytest.raises(image_sanitize.UndecodableImage):
        image_sanitize.sanitize(_animated_png(3))


def test_frames_up_to_the_cap_pass(monkeypatch):
    monkeypatch.setattr(image_sanitize, "MAX_FRAMES", 3)
    image_sanitize.sanitize(_animated_png(3))
