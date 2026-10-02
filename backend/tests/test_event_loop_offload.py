"""느린 동기 처리가 이벤트 루프를 막지 않는다. (#2835)

- 라우트 형태: 채팅 사진·리포트 PDF 처럼 외부 비동기 호출이 없는 라우트는 `def` 다
  (FastAPI 가 스레드풀로 보낸다). 순수 테스트.
- 동시성: 사진 분석의 저장 단계(사진 축소)를 일부러 느리게 만든 채로 `/healthz` 를
  부르면 바로 응답한다. 예전처럼 저장이 루프에서 돌면 `/healthz` 가 그만큼 기다린다.
  DB 테스트(로컬 skip, CI 실행).
"""
from __future__ import annotations

import inspect
import threading
import time
from uuid import uuid4

import pytest

_JPEG = b"\xff\xd8\xff\xe0\x00\x10JFIF fake-image-bytes"
_SLOW_SECONDS = 1.5


@pytest.mark.parametrize(
    ("module", "name"),
    [
        ("app.api.v1.chat_attachments", "receive_chat_image"),
        ("app.api.v1.member_coach", "send_image_to_coach"),
        ("app.api.v1.trainer", "trainer_send_chat_image"),
        ("app.api.v1.trainer", "trainer_send_report_pdf"),
    ],
)
def test_upload_routes_without_external_awaits_are_sync(module, name):
    import importlib

    fn = getattr(importlib.import_module(module), name)
    assert not inspect.iscoroutinefunction(fn), f"{module}.{name} 는 def 여야 한다"


@pytest.mark.parametrize(
    ("module", "name"),
    [
        ("app.api.v1.diet", "diet_analyze"),
        ("app.api.v1.social", "social_login"),
        ("app.api.v1.places", "places_nearby"),
        ("app.api.v1.trainer", "trainer_search_gyms"),
        ("app.api.v1.trainer", "trainer_set_kakao_gym"),
    ],
)
def test_routes_that_await_external_calls_stay_async(module, name):
    """외부 호출(모델·소셜·카카오)을 기다리는 라우트는 async 로 남고, DB 는 스레드로
    넘긴다 — 그 규칙은 `test_async_route_guard` 가 검사한다."""
    import importlib

    fn = getattr(importlib.import_module(module), name)
    assert inspect.iscoroutinefunction(fn)


def _register(client) -> dict[str, str]:
    email = f"loop-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def test_healthz_answers_while_a_photo_is_being_stored(client, monkeypatch):
    from app.services import diet_photo_service

    real_store = diet_photo_service.store_for_entry
    started = threading.Event()

    def slow_store(*args, **kwargs):
        started.set()
        time.sleep(_SLOW_SECONDS)  # 큰 사진 재인코딩·느린 DB 를 흉내 — 동기 블로킹
        return real_store(*args, **kwargs)

    monkeypatch.setattr(diet_photo_service, "store_for_entry", slow_store)
    h = _register(client)
    result: dict[str, object] = {}

    def analyze():
        result["response"] = client.post(
            "/v1/diet/analyze",
            files={"image": ("food.jpg", _JPEG, "image/jpeg")},
            data={"meal_type": "lunch"},
            headers=h,
        )

    worker = threading.Thread(target=analyze)
    worker.start()
    try:
        assert started.wait(timeout=10), "사진 저장 단계에 들어가지 않았다"
        t0 = time.monotonic()
        health = client.get("/v1/healthz")
        elapsed = time.monotonic() - t0
        still_storing = worker.is_alive()
    finally:
        worker.join(timeout=30)

    assert health.status_code == 200
    assert still_storing, "느린 저장이 끝나기 전에 헬스체크를 불러야 의미가 있다"
    assert elapsed < _SLOW_SECONDS / 2, f"/healthz 가 {elapsed:.2f}s 기다렸다"
    response = result["response"]
    assert response.status_code == 200, response.text
    assert response.json()["points"]["awarded"] == 50
