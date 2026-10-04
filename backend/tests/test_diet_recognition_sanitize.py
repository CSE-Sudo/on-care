"""식단 사진은 정리한 뒤에만 외부 인식 모델로 간다. (#3041)

휴대폰 사진의 EXIF 에는 촬영 위치·시각·기기가 들어 있다. 저장본만 정리하고 외부
인식 모델에는 원본을 보내면 집 좌표가 인식 업체로 나간다. `/diet/analyze` 가

- 인식기에 EXIF 없는 JPEG(회전 적용, 장변 1600 이하)만 넘기는지,
- PNG·WebP 도 같은 정리본으로 바꿔 넘기는지,
- 인식과 저장이 같은 정리본을 쓰는지,
- 읽을 수 없는 사진은 인식·한도 차감 전에 415 로 끝내는지,
- 멱등 재전송은 디코딩 없이 기존 결과를 주는지

를 본다. 인식기는 라우터의 `get_recognizer` 를 바꿔 끼워 받은 바이트를 그대로 잡는다.
엔진 계약(받은 바이트를 그대로 싣는다)은 DB 없이 Gemini·LiteLLM 요청을 잡아 본다.
"""
from __future__ import annotations

import asyncio
import base64
import io
from types import SimpleNamespace
from uuid import uuid4

import pytest
from PIL import Image

from app.schemas.diet import DietAnalysis, RecognizedFood
from tests import image_fixtures

_RAW = '{"foods":[{"name":"김치찌개","calories":420}],"coach_comment":""}'


def _exif_of(data: bytes) -> Image.Exif:
    with Image.open(io.BytesIO(data)) as opened:
        return opened.getexif()


def _assert_clean_jpeg(data: bytes) -> tuple[int, int]:
    """메타데이터 없는 JPEG 인지 확인하고 크기를 돌려준다."""
    assert data[:2] == b"\xff\xd8"
    with Image.open(io.BytesIO(data)) as opened:
        assert opened.format == "JPEG"
        assert "exif" not in opened.info
        exif = opened.getexif()
        assert len(exif) == 0
        assert len(exif.get_ifd(image_fixtures.GPS_IFD)) == 0
        return opened.size


# ---------- 엔진 계약 (DB 없이) ----------


def test_gemini_sends_the_bytes_it_is_given():
    """엔진은 받은 정리본을 그대로 싣는다 — 원본을 따로 구하지 않는다."""
    from app.services.recognizer.gemini import GeminiVisionRecognizer

    sent: list = []

    def generate_content(*, model, contents, config):  # noqa: ARG001
        sent.append(contents[1])
        return SimpleNamespace(text=_RAW)

    rec = GeminiVisionRecognizer.__new__(GeminiVisionRecognizer)
    rec._client = SimpleNamespace(models=SimpleNamespace(generate_content=generate_content))
    rec._model = "test-model"
    data = image_fixtures.JPEG
    asyncio.run(rec.recognize(data, "image/jpeg"))

    assert sent[0].inline_data.data == data
    assert sent[0].inline_data.mime_type == "image/jpeg"


def test_litellm_sends_the_bytes_it_is_given():
    from app.services.recognizer.litellm_vision import LiteLLMVisionRecognizer

    urls: list[str] = []

    def create(*, model, messages, temperature, **_kwargs):  # noqa: ARG001 — max_tokens 등(#3032)
        urls.append(messages[0]["content"][1]["image_url"]["url"])
        return SimpleNamespace(
            choices=[SimpleNamespace(message=SimpleNamespace(content=_RAW))]
        )

    rec = LiteLLMVisionRecognizer.__new__(LiteLLMVisionRecognizer)
    rec._client = SimpleNamespace(
        chat=SimpleNamespace(completions=SimpleNamespace(create=create))
    )
    rec._model = "test-model"
    data = image_fixtures.JPEG
    asyncio.run(rec.recognize(data, "image/jpeg"))

    prefix = "data:image/jpeg;base64,"
    assert urls[0].startswith(prefix)
    assert base64.b64decode(urls[0][len(prefix):]) == data


def test_the_recognition_size_matches_the_app_upload_size():
    """앱이 업로드 전에 줄이는 크기(장변 1600, 품질 85)와 같다 — 인식 정확도 유지."""
    from app.services import image_sanitize

    assert image_sanitize.RECOGNITION_MAX_EDGE == 1600
    assert image_sanitize.RECOGNITION_JPEG_QUALITY == 85


def test_the_fixture_photo_really_carries_a_location():
    """아래 API 테스트의 전제 — 원본에는 위치·기기·시각이 있다."""
    data = image_fixtures.jpeg_bytes(exif=image_fixtures.phone_exif())
    exif = _exif_of(data)
    assert exif[image_fixtures.MODEL] == "TP-1"
    assert exif[image_fixtures.DATETIME].startswith("2026")
    assert exif.get_ifd(image_fixtures.GPS_IFD)[1] == "N"


# ---------- /diet/analyze (DB) ----------


class _CapturingRecognizer:
    name = "capture-test"

    def __init__(self) -> None:
        self.received: list[tuple[bytes, str]] = []

    async def recognize(self, image_bytes: bytes, media_type: str) -> DietAnalysis:
        self.received.append((image_bytes, media_type))
        return DietAnalysis(
            engine=self.name,
            foods=[RecognizedFood(name="바나나", amount_g=120, calories=105)],
        )


@pytest.fixture
def recognizer(monkeypatch) -> _CapturingRecognizer:
    from app.api.v1 import diet as diet_api

    rec = _CapturingRecognizer()
    monkeypatch.setattr(diet_api, "get_recognizer", lambda engine=None: rec)
    return rec


@pytest.fixture
def sanitize_calls(monkeypatch) -> list[int]:
    """`image_sanitize.to_jpeg` 호출 횟수(라우터가 부른 것만)."""
    from app.api.v1 import diet as diet_api

    calls: list[int] = []
    real = diet_api.image_sanitize.to_jpeg

    def spy(*args, **kwargs):
        calls.append(1)
        return real(*args, **kwargs)

    monkeypatch.setattr(
        diet_api, "image_sanitize", SimpleNamespace(
            to_jpeg=spy,
            UndecodableImage=diet_api.image_sanitize.UndecodableImage,
            RECOGNITION_MAX_EDGE=diet_api.image_sanitize.RECOGNITION_MAX_EDGE,
            RECOGNITION_JPEG_QUALITY=diet_api.image_sanitize.RECOGNITION_JPEG_QUALITY,
        )
    )
    return calls


def _register(client) -> tuple[str, dict[str, str]]:
    email = f"exif-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    return client.get("/v1/users/me", headers=headers).json()["id"], headers


def _analyze(client, headers, body: bytes, *, mime: str = "image/jpeg", key=None):
    data = {"meal_type": "lunch"}
    if key:
        data["idempotency_key"] = key
    return client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", body, mime)},
        data=data,
        headers=headers,
    )


def _count(db_session, model, user_id: str) -> int:
    from sqlalchemy import func, select

    db_session.expire_all()
    return int(
        db_session.scalar(
            select(func.count()).select_from(model).where(model.user_id == user_id)
        )
        or 0
    )


def test_the_model_never_sees_the_location_time_or_device(client, recognizer):
    _, h = _register(client)
    original = image_fixtures.jpeg_bytes(exif=image_fixtures.phone_exif())

    r = _analyze(client, h, original)

    assert r.status_code == 200, r.text
    [(sent, media_type)] = recognizer.received
    assert media_type == "image/jpeg"
    assert sent != original
    _assert_clean_jpeg(sent)
    assert b"TestPhone" not in sent
    assert b"TP-1" not in sent
    assert b"2026:10:01" not in sent


def test_a_large_photo_reaches_the_model_at_the_recognition_size(client, recognizer):
    _, h = _register(client)

    r = _analyze(client, h, image_fixtures.jpeg_bytes((2400, 1800)))

    assert r.status_code == 200, r.text
    [(sent, _)] = recognizer.received
    assert _assert_clean_jpeg(sent) == (1600, 1200)


def test_a_small_photo_is_not_enlarged(client, recognizer):
    _, h = _register(client)

    r = _analyze(client, h, image_fixtures.jpeg_bytes((320, 240)))

    assert r.status_code == 200, r.text
    [(sent, _)] = recognizer.received
    assert _assert_clean_jpeg(sent) == (320, 240)


@pytest.mark.parametrize(
    ("body", "mime"),
    [
        (image_fixtures.PNG, "image/png"),
        (image_fixtures.WEBP, "image/webp"),
    ],
)
def test_png_and_webp_reach_the_model_as_clean_jpeg(client, recognizer, body, mime):
    _, h = _register(client)

    r = _analyze(client, h, body, mime=mime)

    assert r.status_code == 200, r.text
    [(sent, media_type)] = recognizer.received
    assert media_type == "image/jpeg"
    assert _assert_clean_jpeg(sent) == (64, 48)


def test_a_rotated_phone_photo_reaches_the_model_upright(client, recognizer):
    """회전 태그를 버리기 전에 픽셀에 적용한다 — 세로 사진은 세로로 간다."""
    _, h = _register(client)
    landscape_pixels = image_fixtures.jpeg_bytes(
        (80, 40), exif=image_fixtures.phone_exif(orientation=6)
    )

    r = _analyze(client, h, landscape_pixels)

    assert r.status_code == 200, r.text
    [(sent, _)] = recognizer.received
    assert _assert_clean_jpeg(sent) == (40, 80)


def test_the_stored_photo_comes_from_the_same_clean_copy(client, monkeypatch, recognizer):
    """인식과 저장이 같은 정리본을 쓴다 — 저장 단계가 받은 바이트가 인식기와 같다."""
    from app.services import diet_photo_service

    stored_from: list[bytes] = []
    real_store = diet_photo_service.store_for_entry

    def capture(db, user_id, entry_id, image_bytes):
        stored_from.append(image_bytes)
        return real_store(db, user_id, entry_id, image_bytes)

    monkeypatch.setattr(diet_photo_service, "store_for_entry", capture)
    _, h = _register(client)

    r = _analyze(client, h, image_fixtures.jpeg_bytes(exif=image_fixtures.phone_exif()))

    assert r.status_code == 200, r.text
    [(sent, _)] = recognizer.received
    assert stored_from == [sent]
    photo = client.get(f"/v1{r.json()['photo_url']}", headers=h)
    assert photo.status_code == 200
    _assert_clean_jpeg(photo.content)


@pytest.mark.parametrize(
    "body",
    [
        b"\xff\xd8\xff\xe0\x00\x10JFIF not really a jpeg",
        b"\x89PNG\r\n\x1a\n" + b"\x00" * 16,
        b"RIFF\x00\x00\x00\x00WEBPVP8 " + b"\x00" * 8,
    ],
)
def test_an_unreadable_photo_is_refused_before_the_model_and_the_quota(
    client, db_session, recognizer, body
):
    """매직 넘버만 맞춘 파일은 외부로 나가지 않고, 하루 분석 몫도 깎지 않는다."""
    from app.models.models import DietAnalysisUsage, DietEntry, DietPhoto, PointsLedger

    user_id, h = _register(client)

    r = _analyze(client, h, body)

    assert r.status_code == 415, r.text
    assert recognizer.received == []
    assert _count(db_session, DietAnalysisUsage, user_id) == 0
    assert _count(db_session, DietEntry, user_id) == 0
    assert _count(db_session, DietPhoto, user_id) == 0
    assert _count(db_session, PointsLedger, user_id) == 0


def test_an_idempotent_retry_skips_decoding_and_the_model(
    client, recognizer, sanitize_calls
):
    _, h = _register(client)
    key = f"exif-{uuid4().hex[:8]}"

    first = _analyze(client, h, image_fixtures.JPEG, key=key)
    assert first.status_code == 200, first.text
    assert len(sanitize_calls) == 1

    again = _analyze(client, h, image_fixtures.JPEG, key=key)

    assert again.status_code == 200, again.text
    assert again.json()["entry_id"] == first.json()["entry_id"]
    assert len(sanitize_calls) == 1
    assert len(recognizer.received) == 1
