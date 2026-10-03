"""업로드 사진 정리 — 회전 적용·메타데이터 제거·해상도 상한. (#2829)

휴대폰 사진의 EXIF 에는 촬영 위치(GPS)·촬영 시각·기기 정보가 들어 있는 경우가
많다. 회원이 집에서 찍은 식사·자세·인바디 결과지 사진을 트레이너와 나누는 것이
**집 좌표**를 나누는 뜻이 되면 안 된다. 끼니 사진(#699)은 이미 이 문제를 막고
있었지만 채팅 사진은 받은 바이트를 그대로 저장해, 같은 사진이 경로에 따라 위치를
싣거나 싣지 않았다. 두 경로가 이 모듈 한 곳을 쓰게 해 한쪽만 고쳐지는 일을 막는다.

정리 규칙(두 경로 공통, [_open_upright]):

* 디코딩 **전에** 헤더의 가로·세로로 크기를 본다(#3040). 바이트 상한(본문 10MB,
  채팅 사진 6MB)은 압축된 크기라, 단색에 가까운 PNG·WebP 는 수백 KB 로 1억 픽셀을
  넘긴다. 펼치면 한 장에 수백 MB 다. 장변·픽셀 수가 상한을 넘으면 펼치지 않고
  거절한다. Pillow 의 폭탄 경고(`DecompressionBombWarning`)도 이 호출 안에서는
  오류로 다룬다 — 기본값은 경고만 내고 그 두 배까지 그대로 디코딩한다. 전역
  `Image.MAX_IMAGE_PIXELS` 는 바꾸지 않는다(시드·스크립트까지 번진다).
* JPEG 은 `draft` 로 축소 디코딩한다 — 결과 장변 근처까지 1/2·1/4·1/8 로 줄여
  펼치므로 큰 원본도 메모리를 적게 쓴다. 픽셀 상한은 이렇게 줄인 뒤의 크기에 건다.
* 픽셀을 끝까지 디코딩한다 — 매직 넘버만 맞춘 손상·위장 파일은 여기서 걸린다.
* 애니메이션 이미지는 첫 프레임만 쓴다. 프레임 수가 [MAX_FRAMES] 를 넘으면 받지
  않는다.
* EXIF 회전 태그를 픽셀에 적용한다 — 태그를 버린 뒤에도 세로 사진이 세로로 보인다.
* 원본의 메타데이터(`Image.info` — EXIF·XMP·주석·PNG 텍스트 청크 등)를 하나도
  넘기지 않는다. 저장은 새 인코딩이라 넘긴 것만 파일에 들어간다.
* 색 프로필(ICC)만 다시 싣는다 — 위치·기기 같은 개인 정보가 아니라 색을 맞추는
  값이고, 빼면 인바디 결과지처럼 색이 중요한 사진이 탁해진다.

채팅 사진은 **원본 형식을 유지한다**([sanitize]) — PNG 투명도, 글자가 많은
캡처의 화질을 지킨다. 끼니 사진은 카드 크기 축소본이라 JPEG 로 통일한다
([to_jpeg]).
"""
from __future__ import annotations

import io
import warnings
from dataclasses import dataclass

from app.core.config import get_settings

#: 채팅 사진 장변 상한(px). 대화 안에서 크게 펼쳐 봐도 충분하고, 저장 용량을
#: 예측할 수 있게 한다. 이보다 작은 사진은 크기를 바꾸지 않는다.
CHAT_MAX_EDGE = 2048

#: 애니메이션 PNG·WebP 의 프레임 수 상한. 첫 프레임만 쓰지만, 프레임이 수천 장인
#: 파일은 사진이 아니다.
MAX_FRAMES = 100

_JPEG_QUALITY = 88
_WEBP_QUALITY = 88

#: Pillow 형식 이름 → (확장자, media type). 채팅 저장소가 받는 세 가지다.
_FORMATS: dict[str, tuple[str, str]] = {
    "JPEG": ("jpg", "image/jpeg"),
    "PNG": ("png", "image/png"),
    "WEBP": ("webp", "image/webp"),
}


class UndecodableImage(Exception):
    """이미지로 읽을 수 없다(손상·위장·지원하지 않는 형식)."""


@dataclass(frozen=True)
class CleanImage:
    data: bytes
    extension: str
    media_type: str
    width: int
    height: int


def _open_upright(data: bytes, max_edge: int):
    """디코딩 → 회전 적용 → 장변 축소. 메타데이터가 비어 있는 새 이미지를 돌려준다.

    반환값은 (이미지, 원본 Pillow 형식, ICC 프로필) 이다.
    """
    try:
        from PIL import Image, ImageOps
    except ImportError as exc:  # pragma: no cover - 운영/CI 에는 항상 설치돼 있다
        raise UndecodableImage("이미지를 처리할 수 없습니다.") from exc

    try:
        with warnings.catch_warnings():
            # 폭탄 경고를 이 호출 안에서만 예외로 바꾼다(#3040). 경고는 `Image.open`
            # 이 헤더를 읽을 때 나므로 open 까지 감싼다.
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            return _decode(Image, ImageOps, data, max_edge)
    except UndecodableImage:
        raise
    except Exception as exc:  # noqa: BLE001 - 손상·폭탄·위장 파일 모두 여기서 끝난다
        raise UndecodableImage("이미지를 읽을 수 없습니다.") from exc


def check_dimensions(width: int, height: int) -> None:
    """디코딩할 크기가 상한 안인지 본다. 넘으면 [UndecodableImage]. (#3040)

    장변 상한은 가늘고 긴 이미지(1×1억)를 막고, 픽셀 수 상한은 펼친 메모리를
    막는다. 두 값은 설정(`MAX_IMAGE_DECODE_EDGE`·`MAX_IMAGE_DECODE_PIXELS`)이다.
    """
    settings = get_settings()
    if width < 1 or height < 1:
        raise UndecodableImage("이미지를 읽을 수 없습니다.")
    if max(width, height) > settings.max_image_decode_edge:
        raise UndecodableImage("이미지가 너무 큽니다.")
    if width * height > settings.max_image_decode_pixels:
        raise UndecodableImage("이미지가 너무 큽니다.")


def _decode(Image, ImageOps, data: bytes, max_edge: int):
    """[_open_upright] 의 본체. 예외 변환은 부르는 쪽이 한다."""
    with Image.open(io.BytesIO(data)) as source:
        source_format = source.format or ""
        # 헤더만 읽은 상태다. 원본 크기부터 본다 — 장변이 터무니없으면 축소
        # 디코딩도 하지 않는다.
        width, height = source.size
        if max(width, height) > get_settings().max_image_decode_edge:
            raise UndecodableImage("이미지가 너무 큽니다.")
        if getattr(source, "n_frames", 1) > MAX_FRAMES:
            raise UndecodableImage("이미지를 읽을 수 없습니다.")
        if source_format == "JPEG":
            # 결과 장변 근처까지 줄여 펼친다. 회전 전이라 정사각 상자로 묻는다.
            source.draft(None, (max_edge, max_edge))
        # 실제로 펼칠 크기(JPEG 은 줄인 뒤)에 픽셀 상한을 건다.
        check_dimensions(*source.size)
        # 끝까지 디코딩한다 — 머리만 맞고 몸이 깨진 파일을 저장하지 않는다.
        # 애니메이션이면 첫 프레임만 펼쳐진다.
        source.load()
        icc_profile = source.info.get("icc_profile")
        image = ImageOps.exif_transpose(source)
        # 팔레트·회색조의 투명색은 `info["transparency"]` 에 있다. 아래에서
        # info 를 비우기 전에 알파 채널로 옮겨야 PNG 투명도가 남는다.
        if "transparency" in image.info or image.mode in ("P", "PA", "LA"):
            has_alpha = (
                "transparency" in image.info or image.mode in ("PA", "LA")
            )
            image = image.convert("RGBA" if has_alpha else "RGB")
        elif image.mode not in ("RGB", "RGBA", "L"):
            image = image.convert("RGB")
        image.thumbnail((max_edge, max_edge), Image.LANCZOS)
        # 회전·변환이 없으면 같은 객체가 돌아올 수 있다 — 원본 info 가 저장
        # 단계로 새지 않게 픽셀만 새 이미지로 옮긴다.
        clean = Image.new(image.mode, image.size)
        clean.paste(image)
        return clean, source_format, icc_profile


def sanitize(data: bytes, *, max_edge: int = CHAT_MAX_EDGE) -> CleanImage:
    """채팅 사진 정리 — 원본 형식(JPG·PNG·WebP)을 유지해 다시 인코딩한다.

    받는 형식이 아니거나 디코딩할 수 없으면 [UndecodableImage].
    """
    image, source_format, icc_profile = _open_upright(data, max_edge)
    if source_format not in _FORMATS:
        raise UndecodableImage("JPG·PNG·WebP 이미지만 보낼 수 있습니다.")
    extension, media_type = _FORMATS[source_format]

    options: dict[str, object] = {}
    if icc_profile:
        options["icc_profile"] = icc_profile
    if source_format == "JPEG":
        if image.mode == "RGBA":  # pragma: no cover - JPEG 원본에는 알파가 없다
            image = image.convert("RGB")
        options.update(quality=_JPEG_QUALITY, optimize=True)
    elif source_format == "PNG":
        options.update(optimize=True)
    else:
        options.update(quality=_WEBP_QUALITY, method=4)

    buffer = io.BytesIO()
    try:
        image.save(buffer, format=source_format, **options)
    except Exception as exc:  # noqa: BLE001
        raise UndecodableImage("이미지를 처리할 수 없습니다.") from exc
    return CleanImage(
        data=buffer.getvalue(),
        extension=extension,
        media_type=media_type,
        width=image.width,
        height=image.height,
    )


def to_jpeg(data: bytes, *, max_edge: int, quality: int) -> CleanImage:
    """끼니 사진 정리 — 같은 규칙으로 정리한 뒤 JPEG 하나로 통일한다."""
    image, _, icc_profile = _open_upright(data, max_edge)
    if image.mode != "RGB":
        image = image.convert("RGB")
    options: dict[str, object] = {"quality": quality, "optimize": True}
    if icc_profile:
        options["icc_profile"] = icc_profile
    buffer = io.BytesIO()
    try:
        image.save(buffer, format="JPEG", **options)
    except Exception as exc:  # noqa: BLE001
        raise UndecodableImage("이미지를 처리할 수 없습니다.") from exc
    return CleanImage(
        data=buffer.getvalue(),
        extension="jpg",
        media_type="image/jpeg",
        width=image.width,
        height=image.height,
    )
