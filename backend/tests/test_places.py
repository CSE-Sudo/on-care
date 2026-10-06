"""장소(O2O) — 카카오 실검색 + 시드 폴백(#255).

- docs_to_places 파싱 / _use_kakao 해석은 순수(로컬 실행).
- 엔드포인트(폴백·카카오 경로)는 DB 필요(로컬 skip, CI 실행).
"""
from __future__ import annotations


def test_kakao_merges_all_categories_when_none(monkeypatch):
    """category 생략 시 네 카테고리를 모두 검색·병합하고, 각 결과를 계약 카테고리로
    태깅한다(응답 category 가 빈 문자열이 되지 않음 — 시드 provider 와 의미 일치)."""
    import asyncio

    import httpx

    from app.services.places import kakao

    kakao._cache.clear()
    seen_queries: list[str] = []

    async def fake_get(self, url, params=None, headers=None):
        q = params["query"]
        seen_queries.append(q)

        class _Resp:
            def raise_for_status(self):
                pass

            def json(self):
                return {"documents": [{
                    "id": f"id-{q}", "place_name": q, "x": "127.0", "y": "37.5",
                    "distance": str(len(seen_queries) * 10),
                }]}

        return _Resp()

    monkeypatch.setattr(httpx.AsyncClient, "get", fake_get)
    out = asyncio.run(kakao.search_nearby(37.5, 127.0, None, 1000, "key"))

    assert set(seen_queries) == {"병원", "헬스장", "샐러드", "약국"}  # 네 카테고리 모두 검색
    assert out and all(
        p.category in {"medical", "fitness", "healthy_food", "pharmacy"} for p in out
    )
    assert not any(p.category == "" for p in out)  # 빈 category 없음
    kakao._cache.clear()


def test_kakao_all_category_search_keeps_successful_groups(monkeypatch):
    """전체 검색 중 일부 카테고리 실패가 성공한 카테고리 결과까지 버리지 않는다."""
    import asyncio

    from app.schemas.misc_api import PlaceOut
    from app.services.places import kakao

    kakao._cache.clear()

    async def fake_search(client, lat, lng, category, radius_m, api_key):
        if category == "medical":
            raise RuntimeError("temporary provider failure")
        return [
            PlaceOut(
                id=f"id-{category}",
                name=category,
                category=category,
                address="서울",
                distance_meters=10,
                lat=lat,
                lng=lng,
            )
        ]

    monkeypatch.setattr(kakao, "_search_one", fake_search)
    try:
        out = asyncio.run(kakao.search_nearby(37.5, 127.0, None, 1000, "key"))
        assert {place.category for place in out} == {
            "fitness",
            "healthy_food",
            "pharmacy",
        }
    finally:
        kakao._cache.clear()


def test_kakao_single_category_failure_still_propagates(monkeypatch):
    """단일 카테고리 실패는 라우터의 기존 시드 폴백 경로로 전달한다."""
    import asyncio

    import pytest

    from app.services.places import kakao

    kakao._cache.clear()

    async def fail_search(*args, **kwargs):
        raise RuntimeError("temporary provider failure")

    monkeypatch.setattr(kakao, "_search_one", fail_search)
    try:
        with pytest.raises(RuntimeError, match="temporary provider failure"):
            asyncio.run(
                kakao.search_nearby(37.5, 127.0, "fitness", 1000, "key")
            )
    finally:
        kakao._cache.clear()


def test_kakao_empty_result_not_cached(monkeypatch):
    """일시적 0건은 캐시하지 않는다 — 다음 요청이 다시 실검색을 시도(seed 폴백 고정 방지, #282)."""
    import asyncio

    import httpx

    from app.services.places import kakao

    kakao._cache.clear()

    async def fake_get(self, url, params=None, headers=None):
        class _Resp:
            def raise_for_status(self):
                pass

            def json(self):
                return {"documents": []}

        return _Resp()

    monkeypatch.setattr(httpx.AsyncClient, "get", fake_get)
    out = asyncio.run(kakao.search_nearby(37.5, 127.0, "fitness", 1000, "key"))
    assert out == []
    assert len(kakao._cache) == 0  # 빈 결과는 캐시에 남지 않음
    kakao._cache.clear()


def test_kakao_docs_to_places_parsing():
    from app.services.places.kakao import docs_to_places

    docs = [
        {
            "id": "1", "place_name": "온케어짐", "x": "127.0", "y": "37.5",
            "distance": "120", "road_address_name": "서울 서대문구 신촌로 120",
        },
        {"id": "2", "place_name": "좌표없음"},  # x/y 없음 → 스킵
        {"id": "3", "place_name": "거리없음", "x": "127.1", "y": "37.6"},  # distance 없음 → 0
    ]
    out = docs_to_places(docs, "fitness")
    assert len(out) == 2
    assert out[0].name == "온케어짐"
    assert out[0].category == "fitness"
    assert out[0].distance_meters == 120
    assert out[0].lat == 37.5 and out[0].lng == 127.0
    assert out[1].distance_meters == 0


def test_use_kakao_resolution():
    from app.api.v1.places import _use_kakao
    from app.core.config import Settings

    seed_forced = Settings(_env_file=None, places_provider="seed", kakao_rest_api_key="k")
    kakao_forced = Settings(_env_file=None, places_provider="kakao")
    auto_with_key = Settings(_env_file=None, places_provider="auto", kakao_rest_api_key="k")
    auto_no_key = Settings(_env_file=None, places_provider="auto", kakao_rest_api_key="")
    assert _use_kakao(seed_forced) is False
    assert _use_kakao(kakao_forced) is True
    assert _use_kakao(auto_with_key) is True
    assert _use_kakao(auto_no_key) is False


def test_places_provider_rejects_unknown_value():
    import pytest
    from pydantic import ValidationError

    from app.core.config import Settings

    with pytest.raises(ValidationError):
        Settings(_env_file=None, places_provider="unknown")


def test_places_fallback_to_seed_without_key(client):
    # 기본 설정(키 없음, auto) → 시드 폴백
    r = client.get("/v1/places/nearby")
    assert r.status_code == 200, r.text
    data = r.json()
    assert len(data) >= 1
    assert all("category" in p and "distance_meters" in p for p in data)
    # 거리순 정렬
    dists = [p["distance_meters"] for p in data]
    assert dists == sorted(dists)


def test_places_category_filter_seed(client):
    r = client.get("/v1/places/nearby", params={"category": "fitness"})
    assert r.status_code == 200, r.text
    assert all(p["category"] == "fitness" for p in r.json())


def test_places_uses_kakao_when_configured(client, monkeypatch):
    """카카오 경로: search_nearby 를 가짜로 대체해 네트워크 없이 검증."""
    import app.api.v1.places as places_mod
    from app.core.config import get_settings
    from app.schemas.misc_api import PlaceOut

    async def fake_search(lat, lng, category, radius_m, api_key, timeout):
        assert api_key == "test-key"
        return [PlaceOut(
            id="kk1", name="카카오헬스장", category=category or "",
            address="서울 어딘가", distance_meters=50, lat=lat, lng=lng,
        )]

    monkeypatch.setattr(places_mod.kakao, "search_nearby", fake_search)
    s = get_settings()
    monkeypatch.setattr(s, "kakao_rest_api_key", "test-key")
    monkeypatch.setattr(s, "places_provider", "kakao")

    r = client.get("/v1/places/nearby", params={"category": "fitness", "lat": 37.5, "lng": 127.0})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body[0]["id"] == "kk1"
    assert body[0]["name"] == "카카오헬스장"


def test_places_kakao_wait_does_not_hold_db_connection(client, monkeypatch):
    """카카오를 기다리는 동안 요청 세션이 트랜잭션(연결)을 쥐지 않는다(#3242)."""
    import app.api.v1.places as places_mod
    from app.core.config import get_settings

    seen: dict = {}
    real_release = places_mod.release_connection

    def spy_release(db):
        seen["db"] = db
        return real_release(db)

    async def fake_search(lat, lng, category, radius_m, api_key, timeout):
        seen["in_transaction"] = seen["db"].in_transaction()
        return []

    monkeypatch.setattr(places_mod, "release_connection", spy_release)
    monkeypatch.setattr(places_mod.kakao, "search_nearby", fake_search)
    s = get_settings()
    monkeypatch.setattr(s, "kakao_rest_api_key", "test-key")
    monkeypatch.setattr(s, "places_provider", "kakao")

    r = client.get("/v1/places/nearby", params={"category": "fitness"})
    assert r.status_code == 200, r.text
    assert seen["in_transaction"] is False


def test_places_input_validation(client):
    """좌표 범위·category 허용값 밖은 DB 500 이 아니라 422(리뷰 재-#5)."""
    assert client.get("/v1/places/nearby", params={"lat": 100}).status_code == 422
    assert client.get("/v1/places/nearby", params={"lat": -100}).status_code == 422
    assert client.get("/v1/places/nearby", params={"lng": 200}).status_code == 422
    assert client.get("/v1/places/nearby", params={"category": "gym"}).status_code == 422
    # 유효 카테고리는 정상
    assert client.get("/v1/places/nearby", params={"category": "fitness"}).status_code == 200


def test_kakao_cache_reduces_calls(monkeypatch):
    """동일 위치·카테고리 반복 조회는 TTL 캐시로 카카오 호출을 한 번만 한다."""
    import asyncio

    import app.services.places.kakao as kk

    kk._cache.clear()
    calls = {"n": 0}

    class _FakeResp:
        def raise_for_status(self):
            return None

        def json(self):
            return {"documents": [
                {"id": "1", "place_name": "P", "x": "127.0", "y": "37.5", "distance": "10"}
            ]}

    class _FakeClient:
        def __init__(self, *a, **k):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *a):
            return False

        async def get(self, *a, **k):
            calls["n"] += 1
            return _FakeResp()

    monkeypatch.setattr(kk.httpx, "AsyncClient", _FakeClient)

    async def _run():
        a = await kk.search_nearby(37.5, 127.0, "fitness", 3000, api_key="k")
        b = await kk.search_nearby(37.5, 127.0, "fitness", 3000, api_key="k")
        return a, b

    try:
        a, b = asyncio.run(_run())
        assert calls["n"] == 1  # 두 번째는 캐시 히트
        assert a[0].name == "P" and b[0].name == "P"
    finally:
        kk._cache.clear()


def test_places_falls_back_when_kakao_raises(client, monkeypatch):
    """카카오 호출이 실패해도 요청은 시드로 폴백해 성공한다."""
    import app.api.v1.places as places_mod
    from app.core.config import get_settings

    async def boom(*a, **k):
        raise RuntimeError("kakao down")

    monkeypatch.setattr(places_mod.kakao, "search_nearby", boom)
    s = get_settings()
    monkeypatch.setattr(s, "kakao_rest_api_key", "test-key")
    monkeypatch.setattr(s, "places_provider", "kakao")

    r = client.get("/v1/places/nearby")
    assert r.status_code == 200, r.text  # 폴백으로 200
