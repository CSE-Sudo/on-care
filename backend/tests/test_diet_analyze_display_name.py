"""영어 화면의 사진 분석 — 음식 표시 이름과 식단평의 언어. (#2850)

영어로 앱을 쓰는 회원이 사진을 분석하면 음식 이름과 끼니 식단평이 늘 한국어였다.
음식 이름(`name`)은 공공 영양 DB 가 한국어로 매칭하는 키라 그대로 두고, 화면 언어
표시 이름(`display_name`)을 함께 받는다. 식단평은 요청 언어로 쓴다.
"""
from __future__ import annotations

import asyncio
import json
from datetime import datetime
from types import SimpleNamespace

import pytest

from app.core import clock
from app.core.locale import _request_locale_ctx

_JPEG = b"\xff\xd8\xff\xe0\x00\x10JFIF fake-image-bytes"

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


@pytest.fixture
def english():
    token = _request_locale_ctx.set("en")
    try:
        yield
    finally:
        _request_locale_ctx.reset(token)


# ── 프롬프트 ─────────────────────────────────────────────────────────────


def test_korean_prompt_is_unchanged():
    from app.services.recognizer.locale_prompt import localized_prompt

    assert localized_prompt("BASE", "ko") == "BASE"


def test_english_prompt_asks_for_display_name_and_english_comment():
    from app.services.recognizer.locale_prompt import localized_prompt

    prompt = localized_prompt("BASE", "en")
    assert prompt.startswith("BASE")
    assert '"display_name"' in prompt
    assert "coach_comment" in prompt
    # 매칭 키는 한국어로 남기라고 분명히 말한다.
    assert "한국어" in prompt


def test_prompt_follows_the_request_locale(english):
    from app.services.recognizer.locale_prompt import localized_prompt

    assert '"display_name"' in localized_prompt("BASE")


def test_prompt_defaults_to_korean_outside_a_request():
    from app.services.recognizer.locale_prompt import localized_prompt

    assert localized_prompt("BASE") == "BASE"


@pytest.mark.parametrize(
    "food, expected",
    [
        ({"display_name": "Kimchi stew"}, "Kimchi stew"),
        ({"display_name": "  Brown \n rice  "}, "Brown rice"),
        ({"display_name": ""}, None),
        ({"display_name": "   "}, None),
        ({"display_name": None}, None),
        ({"display_name": 3}, None),
        ({}, None),
        ("not a dict", None),
    ],
)
def test_display_name_is_cleaned(food, expected):
    from app.services.recognizer.locale_prompt import display_name_of

    assert display_name_of(food) == expected


def test_display_name_is_capped():
    from app.services.recognizer.locale_prompt import DISPLAY_NAME_MAX, display_name_of

    assert len(display_name_of({"display_name": "x" * 500})) == DISPLAY_NAME_MAX


# ── 인식기 파싱·호출 ─────────────────────────────────────────────────────


_RAW = json.dumps({
    "foods": [
        {"name": "김치찌개", "display_name": "Kimchi stew", "calories": 300},
        {"name": "현미밥", "calories": 310},
    ],
    "coach_comment": "Add a protein side next time.",
})


def test_gemini_parser_keeps_korean_name_and_display_name():
    from app.services.recognizer.gemini import GeminiVisionRecognizer

    analysis = GeminiVisionRecognizer.__new__(GeminiVisionRecognizer)._parse(_RAW, 1)
    assert [f.name for f in analysis.foods] == ["김치찌개", "현미밥"]
    assert [f.display_name for f in analysis.foods] == ["Kimchi stew", None]
    assert analysis.coach_comment == "Add a protein side next time."


def test_litellm_parser_keeps_korean_name_and_display_name():
    from app.services.recognizer.litellm_vision import LiteLLMVisionRecognizer

    analysis = LiteLLMVisionRecognizer.__new__(LiteLLMVisionRecognizer)._parse(
        f"```json\n{_RAW}\n```", 1
    )
    assert [f.name for f in analysis.foods] == ["김치찌개", "현미밥"]
    assert [f.display_name for f in analysis.foods] == ["Kimchi stew", None]


def _gemini_with_capture(sent: list):
    from app.services.recognizer.gemini import GeminiVisionRecognizer

    def generate_content(*, model, contents, config):  # noqa: ARG001
        sent.append(contents[0])
        return SimpleNamespace(text=_RAW)

    rec = GeminiVisionRecognizer.__new__(GeminiVisionRecognizer)
    rec._client = SimpleNamespace(models=SimpleNamespace(generate_content=generate_content))
    rec._model = "test-model"
    return rec


def test_gemini_sends_english_instruction_on_english_requests(english):
    from app.services.recognizer.gemini import _PROMPT

    sent: list[str] = []
    asyncio.run(_gemini_with_capture(sent).recognize(_JPEG, "image/jpeg"))
    assert sent[0].startswith(_PROMPT)
    assert '"display_name"' in sent[0]


def test_gemini_sends_the_plain_prompt_on_korean_requests():
    from app.services.recognizer.gemini import _PROMPT

    sent: list[str] = []
    asyncio.run(_gemini_with_capture(sent).recognize(_JPEG, "image/jpeg"))
    assert sent == [_PROMPT]


def test_litellm_sends_english_instruction_on_english_requests(english):
    from app.services.recognizer.litellm_vision import _PROMPT, LiteLLMVisionRecognizer

    sent: list[str] = []

    def create(*, model, messages, temperature):  # noqa: ARG001
        sent.append(messages[0]["content"][0]["text"])
        return SimpleNamespace(
            choices=[SimpleNamespace(message=SimpleNamespace(content=_RAW))]
        )

    rec = LiteLLMVisionRecognizer.__new__(LiteLLMVisionRecognizer)
    rec._client = SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(create=create)))
    rec._model = "test-model"
    asyncio.run(rec.recognize(_JPEG, "image/jpeg"))
    assert sent[0].startswith(_PROMPT)
    assert '"display_name"' in sent[0]


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


def _analyze(client, lang: str):
    return client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data={"meal_type": "lunch"},
        headers={"Accept-Language": lang},
    )


def _entry(client, entry_id: str) -> dict:
    for entry in client.get("/v1/diet/days/2026-08-20").json()["entries"]:
        if entry["id"] == entry_id:
            return entry
    raise AssertionError(f"entry {entry_id} not found")


def test_english_analysis_returns_and_stores_display_names(client, frozen_today):
    r = _analyze(client, "en")
    assert r.status_code == 200, r.text
    body = r.json()
    foods = body["analysis"]["foods"]
    assert [f["display_name"] for f in foods] == [
        "Frozen yogurt",
        "Fruit topping",
        "Granola topping",
    ]
    # 매칭 키는 한국어 그대로다.
    assert foods[0]["name"] == "요거트 아이스크림"

    saved = _entry(client, body["entry_id"])
    assert saved["foods"][0]["display_name"] == "Frozen yogurt"
    assert saved["foods"][0]["name"] == "요거트 아이스크림"


def test_english_analysis_writes_the_meal_review_in_english(client, frozen_today):
    body = _analyze(client, "en").json()
    comment = body["analysis"]["coach_comment"]
    assert comment.startswith("Sodium is low")
    assert _entry(client, body["entry_id"])["ai_comment"] == comment


def test_korean_analysis_has_no_display_name(client, frozen_today):
    body = _analyze(client, "ko").json()
    assert all("display_name" not in f or f["display_name"] is None for f in body["analysis"]["foods"])
    saved = _entry(client, body["entry_id"])
    assert all("display_name" not in f for f in saved["foods"])
    assert "나트륨" in saved["ai_comment"]


def test_nutrition_enrichment_is_the_same_in_both_languages(client, frozen_today):
    """공공 DB 매칭은 한국어 이름으로 하므로 화면 언어가 숫자를 바꾸지 않는다."""
    ko = _analyze(client, "ko").json()["analysis"]
    en = _analyze(client, "en").json()["analysis"]

    def numbers(a):
        return [
            (f["name"], f["calories"], f["sodium_mg"], f["sugar_g"], f["source"])
            for f in a["foods"]
        ]

    assert numbers(ko) == numbers(en)
    assert ko["total_calories"] == en["total_calories"]


def test_put_keeps_display_name_the_app_sends_back(client, frozen_today):
    body = _analyze(client, "en").json()
    eid = body["entry_id"]
    foods = _entry(client, eid)["foods"]
    foods[0]["amount_g"] = 220  # 양만 바꾼 음식 — 표시 이름을 그대로 되돌려 보낸다

    r = client.put(f"/v1/diet/entries/{eid}", json={"foods": foods})
    assert r.status_code == 200, r.text
    assert r.json()["foods"][0]["display_name"] == "Frozen yogurt"


def test_put_without_display_name_drops_it(client, frozen_today):
    """이름을 바꾼 음식은 앱이 표시 이름을 빼고 보낸다 — 회원이 쓴 이름이 보인다."""
    eid = _analyze(client, "en").json()["entry_id"]
    foods = _entry(client, eid)["foods"]
    foods[0].pop("display_name")
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
