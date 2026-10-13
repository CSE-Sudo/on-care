"""사진 분석의 음식 표시 이름(`display_name`)과 식단평. (#2850, #3404)

서버 문장은 한국어 하나다. 분석은 `Accept-Language` 와 무관하게 한국어 음식 이름과
한국어 식단평을 낸다. `display_name` 은 응답 필드로 남아 있지만 서버가 새로 만들지
않는다 — 분석 응답에서는 늘 없고, 모델이 실어 보내도 읽지 않는다. 예전 기록에
저장돼 있거나 클라이언트가 되돌려 보낸 값만 그대로 지킨다.
"""
from __future__ import annotations

import asyncio
import json
from datetime import datetime
from types import SimpleNamespace

import pytest

from app.core import clock

from tests.image_fixtures import JPEG as _JPEG  # 진짜 JPEG — 분석 전 정리가 픽셀을 읽는다(#3041)

#: 오늘은 2026-08-20(목) 12:00 KST 로 고정한다.
_NOW = datetime(2026, 8, 20, 12, 0, tzinfo=clock.SEOUL)


@pytest.fixture(autouse=True)
def _demo_member_auth(request):
    """이 모듈의 엔드포인트 검사는 데모 회원의 기록을 쓰고 읽는다.

    쓰기·삭제 라우트는 데모 폴백 없이 회원 토큰을 요구하므로(#2831), 토큰 없이
    보내던 요청에 데모 회원 토큰을 기본 헤더로 붙인다. 요청마다 `headers=` 를 준
    검사는 그 값이 우선한다. DB 가 필요 없는 순수 검사는 건드리지 않는다.
    """
    if "client" not in request.fixturenames:
        yield
        return
    from app.core.security import create_access_token
    from app.db.init_db import DEMO_USER_ID
    from app.db.session import SessionLocal
    from app.models.models import User

    client = request.getfixturevalue("client")
    with SessionLocal() as db:
        version = db.get(User, DEMO_USER_ID).token_version
    previous = client.headers.get("Authorization")
    client.headers["Authorization"] = (
        f"Bearer {create_access_token(DEMO_USER_ID, token_version=version)}"
    )
    try:
        yield
    finally:
        if previous is None:
            client.headers.pop("Authorization", None)
        else:
            client.headers["Authorization"] = previous


@pytest.fixture
def frozen_today(monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: _NOW)
    return _NOW.date()


# ── 인식기 파싱·호출 ─────────────────────────────────────────────────────


_RAW = json.dumps({
    "foods": [
        {"name": "김치찌개", "display_name": "Kimchi stew", "calories": 300},
        {"name": "현미밥", "calories": 310},
    ],
    "coach_comment": "다음에는 단백질 반찬을 곁들여 보세요.",
})


def test_gemini_parser_ignores_a_display_name_from_the_model():
    from app.services.recognizer.gemini import GeminiVisionRecognizer

    analysis = GeminiVisionRecognizer.__new__(GeminiVisionRecognizer)._parse(_RAW, 1)
    assert [f.name for f in analysis.foods] == ["김치찌개", "현미밥"]
    assert [f.display_name for f in analysis.foods] == [None, None]
    assert analysis.coach_comment == "다음에는 단백질 반찬을 곁들여 보세요."


def test_litellm_parser_ignores_a_display_name_from_the_model():
    from app.services.recognizer.litellm_vision import LiteLLMVisionRecognizer

    analysis = LiteLLMVisionRecognizer.__new__(LiteLLMVisionRecognizer)._parse(
        f"```json\n{_RAW}\n```", 1
    )
    assert [f.name for f in analysis.foods] == ["김치찌개", "현미밥"]
    assert [f.display_name for f in analysis.foods] == [None, None]


def _gemini_with_capture(sent: list):
    from app.services.recognizer.gemini import GeminiVisionRecognizer

    def generate_content(*, model, contents, config):  # noqa: ARG001
        sent.append(contents[0])
        return SimpleNamespace(text=_RAW)

    rec = GeminiVisionRecognizer.__new__(GeminiVisionRecognizer)
    rec._client = SimpleNamespace(models=SimpleNamespace(generate_content=generate_content))
    rec._model = "test-model"
    return rec


def test_gemini_sends_the_plain_prompt():
    from app.services.recognizer.gemini import _PROMPT

    sent: list[str] = []
    asyncio.run(_gemini_with_capture(sent).recognize(_JPEG, "image/jpeg"))
    assert sent == [_PROMPT]


# ── 저장 표현 ────────────────────────────────────────────────────────────


def test_store_foods_keeps_display_name_only_when_present():
    from app.schemas.diet import RecognizedFood
    from app.services.diet_service import load_foods, store_foods

    stored = store_foods([
        RecognizedFood(name="김치찌개", display_name="Kimchi stew"),
        RecognizedFood(name="현미밥"),
    ])
    assert stored[0]["display_name"] == "Kimchi stew"
    assert "display_name" not in stored[1]
    assert load_foods(json.dumps(stored, ensure_ascii=False))[0]["display_name"] == "Kimchi stew"


# ── API ─────────────────────────────────────────────────────────────────


def _analyze(client, lang: str | None = None):
    return client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
        headers={"Accept-Language": lang} if lang else None,
    )


def _entry(client, entry_id: str) -> dict:
    for entry in client.get("/v1/diet/days/2026-08-20").json()["entries"]:
        if entry["id"] == entry_id:
            return entry
    raise AssertionError(f"entry {entry_id} not found")


@pytest.mark.parametrize("lang", [None, "ko", "en", "en-US,en;q=0.9"])
def test_analysis_is_korean_and_has_no_display_name_whatever_the_header(
    client, frozen_today, lang
):
    r = _analyze(client, lang)
    assert r.status_code == 200, r.text
    body = r.json()
    foods = body["analysis"]["foods"]
    assert foods[0]["name"] == "요거트 아이스크림"
    assert all(f.get("display_name") is None for f in foods)
    assert "나트륨" in body["analysis"]["coach_comment"]

    saved = _entry(client, body["entry_id"])
    assert all("display_name" not in f for f in saved["foods"])
    assert saved["ai_comment"] == body["analysis"]["coach_comment"]


def test_analysis_numbers_do_not_depend_on_the_header(client, frozen_today):
    default = _analyze(client).json()["analysis"]
    en = _analyze(client, "en").json()["analysis"]

    def numbers(a):
        return [
            (f["name"], f["calories"], f["sodium_mg"], f["sugar_g"], f["source"])
            for f in a["foods"]
        ]

    assert numbers(default) == numbers(en)
    assert default["total_calories"] == en["total_calories"]
    assert default["coach_comment"] == en["coach_comment"]


def test_put_keeps_display_name_the_app_sends_back(client, frozen_today):
    """예전 기록의 표시 이름을 앱이 되돌려 보내면 그대로 저장하고 돌려준다."""
    body = _analyze(client, "en").json()
    eid = body["entry_id"]
    foods = _entry(client, eid)["foods"]
    foods[0]["display_name"] = "Frozen yogurt"
    foods[0]["amount_g"] = 220

    r = client.put(f"/v1/diet/entries/{eid}", json={"foods": foods})
    assert r.status_code == 200, r.text
    assert r.json()["foods"][0]["display_name"] == "Frozen yogurt"


def test_put_without_display_name_drops_it(client, frozen_today):
    """이름을 바꾼 음식은 앱이 표시 이름을 빼고 보낸다 — 회원이 쓴 이름이 보인다."""
    eid = _analyze(client, "en").json()["entry_id"]
    foods = _entry(client, eid)["foods"]
    foods[0]["display_name"] = "Frozen yogurt"
    assert client.put(f"/v1/diet/entries/{eid}", json={"foods": foods}).status_code == 200
    foods = _entry(client, eid)["foods"]
    assert foods[0].pop("display_name") == "Frozen yogurt"
    foods[0]["name"] = "Greek yogurt"

    r = client.put(f"/v1/diet/entries/{eid}", json={"foods": foods})
    assert r.status_code == 200, r.text
    assert "display_name" not in r.json()["foods"][0]
    assert r.json()["foods"][0]["name"] == "Greek yogurt"


def test_put_rejects_overlong_display_name(client, frozen_today):
    eid = _analyze(client, "en").json()["entry_id"]
    foods = _entry(client, eid)["foods"]
    foods[0]["display_name"] = "x" * 81

    r = client.put(f"/v1/diet/entries/{eid}", json={"foods": foods})
    assert r.status_code == 422, r.text
