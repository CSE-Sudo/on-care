"""음식을 찾지 못한 사진 — 빈 끼니 저장·포인트 적립 금지. (#2848)

앞쪽은 프롬프트만 보는 순수 테스트, 뒤쪽은 `/diet/analyze` 를 부르는 DB 테스트다
(로컬 skip, CI 실행). 인식기는 라우터가 쓰는 `get_recognizer` 를 바꿔 끼워 고정한다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest
from sqlalchemy import func, select

from app.schemas.diet import DietAnalysis, RecognizedFood

from tests.image_fixtures import JPEG as _JPEG  # 진짜 JPEG — 분석 전 정리가 픽셀을 읽는다(#3041)


# ---------- 프롬프트 ----------


@pytest.mark.parametrize(
    "module",
    ["app.services.recognizer.gemini", "app.services.recognizer.litellm_vision"],
)
def test_prompts_ask_for_an_empty_list_when_no_food_is_visible(module):
    """모델이 엉뚱한 음식을 지어내지 않게 빈 배열을 명시한다."""
    import importlib

    prompt = importlib.import_module(module)._PROMPT
    assert "음식이 보이지 않으면" in prompt
    assert "빈 배열" in prompt


# ---------- /diet/analyze (DB) ----------


class _FixedRecognizer:
    """정해 둔 결과를 돌려주는 인식기. 몇 번 불렸는지 센다."""

    name = "fixed-test"

    def __init__(self, foods: list[RecognizedFood]):
        self._foods = foods
        self.calls = 0

    async def recognize(self, image_bytes: bytes, media_type: str) -> DietAnalysis:
        self.calls += 1
        return DietAnalysis(
            engine=self.name,
            foods=list(self._foods),
            total_calories=sum(f.calories or 0 for f in self._foods),
        )


@pytest.fixture
def use_recognizer(monkeypatch):
    from app.api.v1 import diet as diet_api

    def _install(foods: list[RecognizedFood]) -> _FixedRecognizer:
        rec = _FixedRecognizer(foods)
        monkeypatch.setattr(diet_api, "get_recognizer", lambda engine=None: rec)
        return rec

    return _install


def _register(client) -> tuple[str, dict[str, str]]:
    email = f"nofood-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    return client.get("/v1/users/me", headers=headers).json()["id"], headers


def _analyze(client, headers, *, key: str | None = None):
    data = {"meal_type": "lunch"}
    if key:
        data["idempotency_key"] = key
    return client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data=data,
        headers=headers,
    )


def _count(db_session, model, user_id: str) -> int:
    db_session.expire_all()
    return int(
        db_session.scalar(select(func.count()).select_from(model).where(model.user_id == user_id))
        or 0
    )


def test_no_food_answers_422_and_leaves_no_trace(client, db_session, use_recognizer):
    """끼니·포인트 원장·사진 어느 것도 남지 않는다."""
    from app.models.models import DietEntry, DietPhoto, PointsLedger

    use_recognizer([])
    user_id, h = _register(client)

    r = _analyze(client, h)

    assert r.status_code == 422, r.text
    detail = r.json()["detail"]
    assert detail["code"] == "no_food_detected"
    assert detail["message"]
    assert _count(db_session, DietEntry, user_id) == 0
    assert _count(db_session, PointsLedger, user_id) == 0
    assert _count(db_session, DietPhoto, user_id) == 0
    assert client.get("/v1/users/me/health", headers=h).json()["activity_points"] == 0


def test_no_food_does_not_consume_the_idempotency_key(client, db_session, use_recognizer):
    """같은 키로 다른 사진을 다시 보내면 새로 분석·저장된다(빈 결과가 키를 잡지 않는다)."""
    from app.models.models import DietEntry

    key = f"idem-{uuid4().hex}"
    user_id, h = _register(client)

    use_recognizer([])
    assert _analyze(client, h, key=key).status_code == 422

    rec = use_recognizer([RecognizedFood(name="비빔밥", amount_g=400, calories=600)])
    r = _analyze(client, h, key=key)

    assert r.status_code == 200, r.text
    assert rec.calls == 1
    assert len(r.json()["analysis"]["foods"]) == 1
    assert r.json()["points"]["awarded"] == 50
    assert _count(db_session, DietEntry, user_id) == 1


def test_a_single_recognized_food_is_saved_and_rewarded_as_before(
    client, db_session, use_recognizer
):
    from app.models.models import DietEntry

    use_recognizer([RecognizedFood(name="바나나", amount_g=120, calories=105)])
    user_id, h = _register(client)

    r = _analyze(client, h)

    assert r.status_code == 200, r.text
    assert r.json()["entry_id"]
    assert r.json()["points"]["awarded"] == 50
    assert _count(db_session, DietEntry, user_id) == 1


def test_no_food_keeps_the_day_empty_for_the_member(client, use_recognizer):
    """식단 탭(오늘 집계)에 0kcal 끼니가 생기지 않는다."""
    use_recognizer([])
    _, h = _register(client)

    assert _analyze(client, h).status_code == 422
    today = client.get("/v1/diet/days/today", headers=h).json()
    assert today["entries"] == []
    assert today["total_calories"] == 0
