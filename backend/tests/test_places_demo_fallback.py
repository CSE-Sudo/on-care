"""장소 검색의 데모 시드 폴백은 데모 서버에서만. (#2914)

실서버(데모 시드 꺼짐)에서는
- 카카오가 0건이면 빈 목록, 실패하면 503 — 시드 장소로 채우지 않는다.
- 키가 없어 DB 장소를 읽을 때도 데모 시드 장소 id 는 뺀다.
데모 서버의 기존 폴백(0건·실패 → 시드)은 그대로다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest

from app.core.config import get_settings
from app.schemas.misc_api import PlaceOut


@pytest.fixture
def demo_off(monkeypatch):
    """데모 시드가 꺼진 서버(운영과 같은 조건)."""
    monkeypatch.setattr(get_settings(), "seed_demo_data", False)


@pytest.fixture
def kakao_on(monkeypatch):
    """카카오 경로를 강제로 켠다(네트워크는 각 테스트가 가짜로 바꾼다)."""
    s = get_settings()
    monkeypatch.setattr(s, "kakao_rest_api_key", "test-key")
    monkeypatch.setattr(s, "places_provider", "kakao")


@pytest.fixture
def kakao_seed_only(monkeypatch):
    """키 없이 DB 장소만 읽는 경로."""
    s = get_settings()
    monkeypatch.setattr(s, "kakao_rest_api_key", "")
    monkeypatch.setattr(s, "places_provider", "seed")


def _fake_kakao(monkeypatch, result):
    import app.api.v1.places as places_mod

    calls = {"n": 0}

    async def fake(*a, **k):
        calls["n"] += 1
        if isinstance(result, Exception):
            raise result
        return list(result)

    monkeypatch.setattr(places_mod.kakao, "search_nearby", fake)
    return calls


def _demo_place_ids() -> set[str]:
    from app.db import demo_ids

    return set(demo_ids.demo_place_ids())


# ---- 카카오 경로 ----


def test_real_server_returns_empty_list_when_kakao_finds_nothing(
    client, demo_off, kakao_on, monkeypatch
):
    calls = _fake_kakao(monkeypatch, [])
    r = client.get("/v1/places/nearby", params={"category": "fitness"})
    assert r.status_code == 200, r.text
    assert r.json() == []
    assert calls["n"] == 1


def test_real_server_returns_503_when_kakao_fails(
    client, demo_off, kakao_on, monkeypatch
):
    _fake_kakao(monkeypatch, RuntimeError("kakao down"))
    r = client.get("/v1/places/nearby", params={"lat": 37.5, "lng": 127.0})
    assert r.status_code == 503, r.text
    # 시드 장소가 섞인 200 이 아니다.
    assert "detail" in r.json()


def test_real_server_503_detail_does_not_leak_coordinates(
    client, demo_off, kakao_on, monkeypatch
):
    _fake_kakao(monkeypatch, RuntimeError("GET ...?x=127.123&y=37.456"))
    r = client.get("/v1/places/nearby", params={"lat": 37.456, "lng": 127.123})
    assert r.status_code == 503
    assert "37.456" not in r.text and "127.123" not in r.text


def test_real_server_passes_kakao_results_through(
    client, demo_off, kakao_on, monkeypatch
):
    place = PlaceOut(
        id="9000000001", name="카카오헬스장", category="fitness",
        address="서울 어딘가", distance_meters=40, lat=37.5, lng=127.0,
    )
    _fake_kakao(monkeypatch, [place])
    r = client.get("/v1/places/nearby", params={"category": "fitness"})
    assert r.status_code == 200, r.text
    assert [p["id"] for p in r.json()] == ["9000000001"]


def test_demo_server_still_falls_back_to_seed_on_empty_kakao(
    client, kakao_on, monkeypatch
):
    _fake_kakao(monkeypatch, [])
    r = client.get("/v1/places/nearby")
    assert r.status_code == 200, r.text
    ids = {p["id"] for p in r.json()}
    assert ids & _demo_place_ids()


def test_demo_server_still_falls_back_to_seed_on_kakao_error(
    client, kakao_on, monkeypatch
):
    _fake_kakao(monkeypatch, RuntimeError("kakao down"))
    r = client.get("/v1/places/nearby")
    assert r.status_code == 200, r.text
    assert {p["id"] for p in r.json()} & _demo_place_ids()


# ---- 키 없는 DB 경로 ----


def test_real_server_db_path_hides_demo_seed_places(
    client, db_session, demo_off, kakao_seed_only
):
    from app.models import models

    real_id = f"real-place-{uuid4().hex[:8]}"
    db_session.add(models.Place(
        id=real_id, name="실제 장소", category="fitness", address="",
        lat=37.5571, lng=126.9370,
    ))
    db_session.commit()
    try:
        r = client.get(
            "/v1/places/nearby",
            params={"lat": 37.5571, "lng": 126.9370, "radius_m": 20000},
        )
        assert r.status_code == 200, r.text
        ids = {p["id"] for p in r.json()}
        assert real_id in ids
        assert not ids & _demo_place_ids()
    finally:
        db_session.delete(db_session.get(models.Place, real_id))
        db_session.commit()


def test_demo_server_db_path_keeps_demo_seed_places(client, kakao_seed_only):
    r = client.get(
        "/v1/places/nearby",
        params={"lat": 37.5571, "lng": 126.9370, "radius_m": 20000},
    )
    assert r.status_code == 200, r.text
    assert {p["id"] for p in r.json()} & _demo_place_ids()


def test_seed_nearby_exclude_filters_ids(client, db_session):
    """`_seed_nearby` 의 exclude 인자 단위 확인."""
    from app.api.v1.places import _seed_nearby
    from app.models import models

    keep = f"keep-{uuid4().hex[:8]}"
    drop = f"drop-{uuid4().hex[:8]}"
    for pid in (keep, drop):
        db_session.add(models.Place(
            id=pid, name=pid, category="fitness", address="", lat=37.5, lng=127.0,
        ))
    db_session.flush()
    out = _seed_nearby(db_session, 37.5, 127.0, "fitness", 1000, exclude=frozenset({drop}))
    ids = {p.id for p in out}
    assert keep in ids
    assert drop not in ids
    db_session.rollback()
