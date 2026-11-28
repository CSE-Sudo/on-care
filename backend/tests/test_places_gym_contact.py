"""주변 검색의 전화번호와 헬스장 판별. (#3357)

카카오에서만 찾은 헬스장은 가입한 트레이너가 없어 상담을 걸 수 없다. 회원이 문의할
길은 전화뿐인데 주변 검색이 번호를 버렸고, "헬스장" 검색어에 걸린 다른 업종도 그대로
실었다. 트레이너 소속 검색(`docs_to_gyms`)과 같은 판별·같은 번호를 쓰는지 본다.

파싱·병합은 순수 함수라 DB 없이 돈다. 엔드포인트 테스트는 DB 가 필요하다(로컬 skip,
CI 실행).
"""
from __future__ import annotations

import asyncio
from uuid import uuid4

import pytest

from app.core.config import get_settings
from app.services.places import kakao

GYM_CATEGORY = "스포츠,레저 > 스포츠시설 > 헬스클럽"
PILATES_CATEGORY = "스포츠,레저 > 스포츠시설 > 필라테스"
SHOP_CATEGORY = "가정,생활 > 스포츠용품 > 헬스용품"


def _doc(
    place_id: str,
    name: str,
    *,
    category: str | None = GYM_CATEGORY,
    phone: str | None = "02-111-2222",
    distance: str = "100",
) -> dict:
    doc = {
        "id": place_id,
        "place_name": name,
        "road_address_name": f"서울 마포구 {name}로 1",
        "x": "126.9380",
        "y": "37.5570",
        "distance": distance,
    }
    if category is not None:
        doc["category_name"] = category
    if phone is not None:
        doc["phone"] = phone
    return doc


@pytest.fixture
def kakao_http(monkeypatch):
    """카카오 HTTP 응답을 바꿔 끼운다 — 검색어별 documents 를 돌려준다."""
    import httpx

    kakao._cache.clear()
    docs_by_query: dict[str, list[dict]] = {}

    async def fake_get(self, url, params=None, headers=None):
        docs = docs_by_query.get(params["query"], [])

        class _Resp:
            def raise_for_status(self):
                pass

            def json(self):
                return {"documents": docs}

        return _Resp()

    monkeypatch.setattr(httpx.AsyncClient, "get", fake_get)
    yield docs_by_query
    kakao._cache.clear()


# ---- 파싱 ----


def test_fitness_keeps_only_sports_facilities():
    docs = [
        _doc("1", "온케어짐"),
        _doc("2", "온케어필라테스", category=PILATES_CATEGORY),
        _doc("3", "헬스장용품마트", category=SHOP_CATEGORY),
        _doc("4", "분류없음", category=None),
        _doc("5", "분류빈값", category=""),
    ]
    out = kakao.docs_to_places(docs, "fitness")
    assert [p.id for p in out] == ["1", "2"]
    assert all(p.category == "fitness" for p in out)


def test_fitness_filter_matches_trainer_gym_search():
    """회원용 주변 검색과 트레이너 소속 검색이 같은 장소를 헬스장으로 본다."""
    docs = [
        _doc("1", "온케어짐"),
        _doc("2", "온케어필라테스", category=PILATES_CATEGORY),
        _doc("3", "헬스장용품마트", category=SHOP_CATEGORY),
    ]
    member = {p.id for p in kakao.docs_to_places(docs, "fitness")}
    trainer = {g["id"] for g in kakao.docs_to_gyms(docs)}
    assert member == trainer


@pytest.mark.parametrize("category", ["medical", "healthy_food", "pharmacy", None])
def test_other_categories_are_not_filtered(category):
    """헬스장 판별은 `fitness` 에만 건다 — 병원·약국·건강식은 그대로 싣는다."""
    docs = [
        _doc("1", "온케어내과", category="의료,건강 > 병원 > 내과"),
        _doc("2", "분류없음", category=None),
    ]
    out = kakao.docs_to_places(docs, category)
    assert [p.id for p in out] == ["1", "2"]


def test_phone_is_carried():
    out = kakao.docs_to_places([_doc("1", "온케어짐", phone="02-333-4444")], "fitness")
    assert out[0].phone == "02-333-4444"


@pytest.mark.parametrize("phone", [None, ""])
def test_missing_phone_is_null(phone):
    out = kakao.docs_to_places([_doc("1", "온케어짐", phone=phone)], "fitness")
    assert len(out) == 1
    assert out[0].phone is None


def test_phone_is_carried_for_other_categories():
    docs = [_doc("1", "온케어약국", category="의료,건강 > 약국", phone="02-555-6666")]
    assert kakao.docs_to_places(docs, "pharmacy")[0].phone == "02-555-6666"


def test_phone_matches_trainer_gym_search():
    docs = [_doc("1", "온케어짐", phone="02-777-8888")]
    assert (
        kakao.docs_to_places(docs, "fitness")[0].phone
        == kakao.docs_to_gyms(docs)[0]["phone"]
    )


# ---- search_nearby ----


def test_search_nearby_fitness_drops_non_gyms(kakao_http):
    kakao_http["헬스장"] = [
        _doc("shop", "헬스장용품마트", category=SHOP_CATEGORY, distance="10"),
        _doc("gym", "온케어짐", distance="50"),
    ]
    out = asyncio.run(kakao.search_nearby(37.5, 127.0, "fitness", 1000, "key"))
    assert [p.id for p in out] == ["gym"]
    assert out[0].phone == "02-111-2222"


def test_search_nearby_all_categories_filters_only_fitness(kakao_http):
    kakao_http["헬스장"] = [
        _doc("shop", "헬스장용품마트", category=SHOP_CATEGORY, distance="10"),
        _doc("gym", "온케어짐", distance="50"),
    ]
    kakao_http["약국"] = [
        _doc("pharm", "온케어약국", category="의료,건강 > 약국", distance="20"),
    ]
    out = asyncio.run(kakao.search_nearby(37.5, 127.0, None, 1000, "key"))
    assert {p.id: p.category for p in out} == {"gym": "fitness", "pharm": "pharmacy"}


def test_search_nearby_only_non_gyms_is_empty_and_not_cached(kakao_http):
    """걸러서 0건이면 빈 결과다 — 캐시에도 남기지 않는다(#282 와 같은 규칙)."""
    kakao_http["헬스장"] = [_doc("shop", "헬스장용품마트", category=SHOP_CATEGORY)]
    out = asyncio.run(kakao.search_nearby(37.5, 127.0, "fitness", 1000, "key"))
    assert out == []
    assert len(kakao._cache) == 0


# ---- 엔드포인트 ----


@pytest.fixture
def kakao_on(monkeypatch):
    s = get_settings()
    monkeypatch.setattr(s, "kakao_rest_api_key", "test-key")
    monkeypatch.setattr(s, "places_provider", "kakao")


@pytest.fixture
def kakao_seed_only(monkeypatch):
    """키 없이 DB 장소만 읽는 경로."""
    s = get_settings()
    monkeypatch.setattr(s, "kakao_rest_api_key", "")
    monkeypatch.setattr(s, "places_provider", "seed")


def test_endpoint_returns_phone_from_kakao(client, kakao_on, kakao_http):
    kakao_http["헬스장"] = [
        _doc("kk-phone", "온케어짐", phone="02-123-4567"),
        _doc("kk-no-phone", "번호없는짐", phone="", distance="200"),
        _doc("kk-shop", "헬스장용품마트", category=SHOP_CATEGORY, distance="5"),
    ]
    r = client.get(
        "/v1/places/nearby",
        params={"category": "fitness", "lat": 37.5, "lng": 127.0},
    )
    assert r.status_code == 200, r.text
    body = {p["id"]: p for p in r.json()}
    assert set(body) == {"kk-phone", "kk-no-phone"}
    assert body["kk-phone"]["phone"] == "02-123-4567"
    assert body["kk-no-phone"]["phone"] is None


def test_endpoint_db_path_reads_phone_from_gym_profile(
    client, db_session, kakao_seed_only
):
    from app.models import models

    with_phone = f"place-phone-{uuid4().hex[:8]}"
    blank_phone = f"place-blank-{uuid4().hex[:8]}"
    no_profile = f"place-bare-{uuid4().hex[:8]}"
    for pid in (with_phone, blank_phone, no_profile):
        db_session.add(models.Place(
            id=pid, name=pid, category="fitness", address="",
            lat=35.1000, lng=129.0000,
        ))
    db_session.flush()
    db_session.add(models.GymProfile(place_id=with_phone, phone="051-111-2222"))
    db_session.add(models.GymProfile(place_id=blank_phone, phone=""))
    db_session.commit()
    try:
        r = client.get(
            "/v1/places/nearby",
            params={"lat": 35.1000, "lng": 129.0000, "radius_m": 500},
        )
        assert r.status_code == 200, r.text
        body = {p["id"]: p for p in r.json()}
        assert body[with_phone]["phone"] == "051-111-2222"
        assert body[blank_phone]["phone"] is None
        assert body[no_profile]["phone"] is None
    finally:
        # gym_profiles 는 places 삭제에 딸려 지워진다(ondelete=CASCADE).
        for pid in (with_phone, blank_phone, no_profile):
            db_session.delete(db_session.get(models.Place, pid))
        db_session.commit()


def test_seed_nearby_places_without_profile_have_no_phone(client, db_session):
    """병원·약국처럼 `gym_profiles` 가 없는 장소는 번호 없이 그대로 나온다."""
    from app.api.v1.places import _seed_nearby

    out = _seed_nearby(db_session, 37.5571, 126.9370, "pharmacy", 20000)
    assert out
    assert all(p.phone is None for p in out)
