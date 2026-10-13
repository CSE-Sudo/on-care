"""회원용 헬스장 이름 검색 `GET /gyms/search`. (#3355)

등록된 헬스장과 카카오 이름 검색 결과를 합친다. 목록과 달리 반경을 걸지 않고, 상한과
데모 제외는 목록(#3356)과 같다. 카카오 호출은 `kakao.search_gyms` 를 바꿔 끼워
네트워크 없이 돈다. 엔드포인트·서비스 테스트는 DB 가 필요하다(로컬 skip, CI 실행).
"""
from __future__ import annotations

import random

import pytest

from app.core.config import get_settings

SINCHON = {"lat": 37.5559, "lng": 126.9368}
#: 시드 제휴 헬스장 — 카카오에는 없다.
HEALTHMATE_ID = "gym-healthmate"
HEALTHMATE_NAME = "헬스메이트 신촌점"

#: 이 파일만 쓰는 검색어. 시드의 어떤 헬스장 이름·주소에도 없다.
WORD = "이름검색테스트"
FAR_ID = "gym-name-search-busan"
NEAR_ID = "gym-name-search-near"
NO_COORDS_ID = "gym-name-search-no-coords"


def _kakao_doc(
    place_id: str,
    name: str,
    *,
    lat: float = 37.5570,
    lng: float = 126.9380,
    category: str = "스포츠,레저 > 스포츠시설 > 헬스클럽",
    phone: str = "02-111-2222",
) -> dict:
    return {
        "id": place_id,
        "place_name": name,
        "category_name": category,
        "road_address_name": f"서울 마포구 {name}로 1",
        "address_name": "서울 마포구 지번",
        "x": str(lng),
        "y": str(lat),
        "phone": phone,
        "distance": "",
    }


def _new_kakao_id() -> str:
    # 실제 카카오 id 와 겹치지 않을 긴 숫자.
    return str(random.randint(10**14, 10**15 - 1))


@pytest.fixture
def demo_off(monkeypatch):
    """데모 시드가 꺼진 서버(운영과 같은 조건)."""
    monkeypatch.setattr(get_settings(), "seed_demo_data", False)


@pytest.fixture
def named_gyms(db_session):
    """실재 업체 역할의 헬스장 세 곳 — 부산, 신촌 옆, 좌표 없음. 끝나면 지운다."""
    from app.models.models import GymProfile, Place

    ids = [FAR_ID, NEAR_ID, NO_COORDS_ID]
    db_session.add_all([
        Place(
            id=FAR_ID, name=f"{WORD} 부산짐", category="fitness",
            address="부산 해운대구", lat=35.1631, lng=129.1636,
        ),
        Place(
            id=NEAR_ID, name=f"{WORD} 신촌짐", category="fitness",
            address="서울 서대문구", lat=37.5562, lng=126.9370,
        ),
        Place(
            id=NO_COORDS_ID, name=f"{WORD} 좌표없는짐", category="fitness",
            address="주소 미상",
        ),
    ])
    db_session.flush()
    db_session.add(GymProfile(
        place_id=NEAR_ID, rating=4.5, phone="02-333-4444", is_partner=False,
        tags_json='["PT"]',
    ))
    db_session.commit()
    yield
    db_session.rollback()
    db_session.query(GymProfile).filter(
        GymProfile.place_id.in_(ids)
    ).delete(synchronize_session=False)
    db_session.query(Place).filter(Place.id.in_(ids)).delete(synchronize_session=False)
    db_session.commit()


@pytest.fixture
def fake_kakao(monkeypatch):
    """카카오를 켠 것으로 두고, 검색 결과를 테스트가 정한다.

    `docs` 의 카카오 원문은 실제 파서(`docs_to_gyms`)를 거친다. `fail=True` 면 호출이
    예외를 던진다. `calls` 에 받은 (검색어, 위도, 경도, 반경)이 쌓인다.
    """
    from app.services import trainer_gym_search
    from app.services.places import kakao

    state = {"docs": [], "fail": False, "calls": []}

    async def fake_search_gyms(query, lat, lng, api_key, timeout=3.0, radius_m=None):
        state["calls"].append((query, lat, lng, radius_m))
        if state["fail"]:
            raise RuntimeError("kakao down")
        return kakao.docs_to_gyms(state["docs"])

    monkeypatch.setattr(trainer_gym_search, "kakao_enabled", lambda: True)
    monkeypatch.setattr(kakao, "search_gyms", fake_search_gyms)
    return state


@pytest.fixture
def kakao_off(monkeypatch):
    from app.services import trainer_gym_search

    monkeypatch.setattr(trainer_gym_search, "kakao_enabled", lambda: False)


def _search(client, q: str, **params):
    return client.get("/v1/gyms/search", params={"q": q, **params})


def _rows(response) -> list[dict]:
    assert response.status_code == 200, response.text
    return response.json()


def _ids(response) -> list[str]:
    return [g["id"] for g in _rows(response)]


# ---- 이름 키 (순수) ----


def test_name_key_ignores_spacing_and_case():
    from app.services import gym_search

    assert gym_search._name_key("헬스메이트 신촌점") == gym_search._name_key("헬스메이트신촌점")
    assert gym_search._name_key("FIT Lab") == gym_search._name_key("fitlab")
    assert gym_search._name_key("헬스메이트 신촌점") != gym_search._name_key("헬스메이트 홍대점")


def test_kakao_only_gym_has_empty_profile_fields():
    """카카오가 주지 않는 평점·태그·영업시간은 지어내지 않는다."""
    from app.services import gym_search

    doc = {
        "id": "777", "name": "카카오짐", "address": "서울 마포구", "lat": 37.55,
        "lng": 126.93, "phone": "", "distance_meters": None,
    }
    gym = gym_search._from_kakao(doc, None, None)
    assert (gym.id, gym.name, gym.address) == ("777", "카카오짐", "서울 마포구")
    assert gym.rating == 0 and gym.tags == [] and gym.is_partner is False
    assert gym.weekday_hours is None and gym.weekend_hours is None
    assert gym.phone is None  # 빈 문자열을 그대로 내리지 않는다
    assert gym.distance_km == 0  # 좌표 없는 검색


def test_kakao_only_gym_distance_uses_the_same_haversine():
    from app.services import gym_search, gym_service

    doc = {
        "id": "777", "name": "카카오짐", "address": "", "lat": 37.5570,
        "lng": 126.9380, "phone": "02-1", "distance_meters": 999999,
    }
    gym = gym_search._from_kakao(doc, **SINCHON)
    expected = gym_service._haversine_m(SINCHON["lat"], SINCHON["lng"], 37.5570, 126.9380)
    # 카카오가 준 거리가 아니라 등록 헬스장과 같은 계산이다.
    assert gym.distance_km == expected / 1000
    assert gym.phone == "02-1"


# ---- 요청 검증 ----


def test_search_requires_a_query(client, kakao_off):
    assert client.get("/v1/gyms/search").status_code == 422
    assert _search(client, "").status_code == 422
    assert _search(client, "   ").status_code == 422
    assert _search(client, "가" * 101).status_code == 422


def test_search_rejects_half_a_coordinate_pair(client, kakao_off):
    assert _search(client, WORD, lat=37.5).status_code == 422
    assert _search(client, WORD, lng=126.9).status_code == 422
    assert _search(client, WORD, lat=91, lng=126.9).status_code == 422


def test_search_path_is_not_read_as_a_gym_id(client, kakao_off):
    """`/gyms/{gym_id}` 보다 먼저 잡힌다 — 404 가 아니라 검색 응답(배열)이다."""
    r = _search(client, HEALTHMATE_NAME)
    assert r.status_code == 200, r.text
    assert isinstance(r.json(), list)


# ---- 등록 헬스장 ----


def test_search_finds_a_gym_outside_the_list_radius(client, named_gyms, kakao_off):
    """주변 목록(반경 5km)에 없는 부산 헬스장도 이름으로 나온다."""
    nearby = {g["id"] for g in client.get("/v1/gyms", params=SINCHON).json()}
    assert FAR_ID not in nearby

    assert FAR_ID in _ids(_search(client, f"{WORD} 부산", **SINCHON))


def test_search_ignores_spacing_and_word_order(client, named_gyms, kakao_off):
    assert FAR_ID in _ids(_search(client, f"부산짐 {WORD}"))
    assert FAR_ID in _ids(_search(client, f"{WORD}부산짐"))


def test_search_matches_the_address_too(client, named_gyms, kakao_off):
    assert _ids(_search(client, f"해운대 {WORD}")) == [FAR_ID]


def test_search_does_not_treat_wildcards_as_patterns(client, named_gyms, kakao_off):
    assert _ids(_search(client, "%")) == []
    assert _ids(_search(client, "_")) == []


def test_search_returns_gym_out_shape(client, named_gyms, kakao_off):
    by_id = {g["id"]: g for g in _rows(_search(client, WORD, **SINCHON))}
    near = by_id[NEAR_ID]
    assert set(near) == {
        "id", "name", "address", "distance_km", "rating", "tags", "weekday_hours",
        "weekend_hours", "phone", "lat", "lng", "is_partner",
    }
    assert near["rating"] == 4.5
    assert near["tags"] == ["PT"]
    assert near["phone"] == "02-333-4444"
    assert 0 < near["distance_km"] < 1


def test_search_without_coordinates_orders_by_name(client, named_gyms, kakao_off):
    rows = _rows(_search(client, WORD))
    assert [g["id"] for g in rows] == [FAR_ID, NEAR_ID, NO_COORDS_ID]
    assert all(g["distance_km"] == 0 for g in rows)


def test_search_with_coordinates_orders_by_distance(client, named_gyms, kakao_off):
    """가까운 순. 좌표를 모르는 헬스장은 거리 0 이어도 맨 뒤다."""
    assert _ids(_search(client, WORD, **SINCHON)) == [NEAR_ID, FAR_ID, NO_COORDS_ID]


def test_search_with_no_match_is_an_empty_list(client, kakao_off):
    assert _ids(_search(client, "어디에도없는헬스장이름zz")) == []


# ---- 카카오 결과 병합 ----


def test_search_adds_kakao_gyms_that_are_not_registered(client, named_gyms, fake_kakao):
    new_id = _new_kakao_id()
    fake_kakao["docs"] = [_kakao_doc(new_id, f"{WORD} 카카오짐")]

    rows = _rows(_search(client, WORD))
    ids = [g["id"] for g in rows]

    # 좌표 없는 검색: 등록된 헬스장(이름순)이 먼저, 카카오 결과가 그 뒤.
    assert ids == [FAR_ID, NEAR_ID, NO_COORDS_ID, new_id]
    found = rows[-1]
    assert found["name"] == f"{WORD} 카카오짐"
    assert found["rating"] == 0 and found["tags"] == []
    assert found["phone"] == "02-111-2222"
    assert found["is_partner"] is False
    # 이름 검색은 반경을 걸지 않는다.
    assert fake_kakao["calls"] == [(WORD, None, None, None)]


def test_search_does_not_register_kakao_gyms(client, db_session, fake_kakao):
    """회원의 검색이 `places` 를 늘리지 않는다 — 넣는 것은 트레이너의 소속 선택뿐이다."""
    from app.models.models import Place

    new_id = _new_kakao_id()
    fake_kakao["docs"] = [_kakao_doc(new_id, f"{WORD} 카카오짐")]

    assert new_id in _ids(_search(client, WORD))
    db_session.expire_all()
    assert db_session.get(Place, new_id) is None
    # 그래서 단건 조회로는 읽히지 않는다.
    assert client.get(f"/v1/gyms/{new_id}").status_code == 404


def test_search_passes_coordinates_to_kakao_and_sorts_the_merge(
    client, named_gyms, fake_kakao
):
    closest, middle = _new_kakao_id(), _new_kakao_id()
    fake_kakao["docs"] = [
        # 대전 — 신촌짐보다 멀고 부산짐보다 가깝다.
        _kakao_doc(middle, f"{WORD} 대전짐", lat=36.3504, lng=127.3845),
        # 검색 중심 바로 그 자리.
        _kakao_doc(closest, f"{WORD} 코앞짐", lat=SINCHON["lat"], lng=SINCHON["lng"]),
    ]

    rows = _rows(_search(client, WORD, **SINCHON))

    assert [g["id"] for g in rows] == [closest, NEAR_ID, middle, FAR_ID, NO_COORDS_ID]
    distances = [g["distance_km"] for g in rows[:-1]]
    assert distances == sorted(distances)
    assert fake_kakao["calls"] == [(WORD, SINCHON["lat"], SINCHON["lng"], None)]


def test_search_lists_a_registered_kakao_gym_once(client, db_session, fake_kakao):
    """카카오 결과가 이미 `places` 에 있으면 등록 쪽(정보가 더 많다) 한 줄만 싣는다."""
    from app.models.models import GymProfile, Place

    kakao_id = _new_kakao_id()
    db_session.add(Place(
        id=kakao_id, name=f"{WORD} 등록된카카오짐", category="fitness",
        address="서울 마포구", lat=37.55, lng=126.93, kakao_place_id=kakao_id,
    ))
    db_session.flush()
    db_session.add(GymProfile(
        place_id=kakao_id, rating=4.8, phone="02-999-0000", is_partner=False,
    ))
    db_session.commit()
    try:
        fake_kakao["docs"] = [_kakao_doc(kakao_id, "카카오가 준 다른 이름")]

        rows = _rows(_search(client, WORD))
        assert [g["id"] for g in rows] == [kakao_id]
        assert rows[0]["name"] == f"{WORD} 등록된카카오짐"
        assert rows[0]["rating"] == 4.8

        # 이름·주소로는 안 걸려도 카카오가 찾아 주면 등록된 행으로 나온다.
        rows = _rows(_search(client, "카카오가 준 다른 이름"))
        assert [g["id"] for g in rows] == [kakao_id]
        assert rows[0]["rating"] == 4.8
    finally:
        db_session.rollback()
        db_session.query(GymProfile).filter_by(place_id=kakao_id).delete()
        db_session.query(Place).filter_by(id=kakao_id).delete()
        db_session.commit()


def test_search_maps_a_kakao_id_stored_on_another_row(client, db_session, fake_kakao):
    """`places.id` 가 카카오 id 가 아니어도 `kakao_place_id` 가 같으면 같은 헬스장이다."""
    from app.models.models import Place

    kakao_id = _new_kakao_id()
    row_id = "gym-name-search-linked"
    db_session.add(Place(
        id=row_id, name=f"{WORD} 연결된짐", category="fitness",
        address="서울 마포구", lat=37.55, lng=126.93, kakao_place_id=kakao_id,
    ))
    db_session.commit()
    try:
        fake_kakao["docs"] = [_kakao_doc(kakao_id, "카카오쪽 이름")]
        assert _ids(_search(client, "카카오쪽 이름")) == [row_id]
    finally:
        db_session.rollback()
        db_session.query(Place).filter_by(id=row_id).delete()
        db_session.commit()


def test_search_dedupes_a_seed_gym_by_name(client, fake_kakao):
    """시드 제휴 헬스장은 id 가 카카오와 다르다 — 이름이 같으면 등록 쪽만 남긴다."""
    fake_kakao["docs"] = [_kakao_doc(_new_kakao_id(), "헬스메이트신촌점")]

    rows = _rows(_search(client, "헬스메이트"))
    names = [g["name"] for g in rows]
    assert names.count(HEALTHMATE_NAME) == 1
    assert "헬스메이트신촌점" not in names
    assert HEALTHMATE_ID in {g["id"] for g in rows}


def test_search_drops_kakao_results_that_are_not_gyms(client, fake_kakao):
    food = _new_kakao_id()
    fake_kakao["docs"] = [_kakao_doc(food, f"{WORD} 식당", category="음식점 > 한식")]
    assert _ids(_search(client, WORD)) == []


def test_search_survives_a_kakao_failure(client, named_gyms, fake_kakao):
    """외부 검색이 실패해도 등록된 헬스장 결과는 보인다."""
    fake_kakao["fail"] = True

    assert _ids(_search(client, WORD)) == [FAR_ID, NEAR_ID, NO_COORDS_ID]
    assert len(fake_kakao["calls"]) == 1


def test_search_without_kakao_does_not_call_it(client, named_gyms, kakao_off, monkeypatch):
    from app.services.places import kakao

    async def boom(*args, **kwargs):
        raise AssertionError("카카오를 부르면 안 된다")

    monkeypatch.setattr(kakao, "search_gyms", boom)
    assert _ids(_search(client, WORD)) == [FAR_ID, NEAR_ID, NO_COORDS_ID]


# ---- 상한 ----


def test_search_caps_the_merged_result(client, named_gyms, fake_kakao):
    from app.services import gym_service

    fake_kakao["docs"] = [
        _kakao_doc(_new_kakao_id(), f"{WORD} 카카오짐 {i:03d}")
        for i in range(gym_service.DEFAULT_GYM_LIMIT + 10)
    ]
    rows = _rows(_search(client, WORD))
    assert len(rows) == gym_service.DEFAULT_GYM_LIMIT
    # 좌표 없는 검색은 등록된 헬스장이 앞이라 잘려 나가지 않는다.
    assert [g["id"] for g in rows[:3]] == [FAR_ID, NEAR_ID, NO_COORDS_ID]


def test_service_limit_keeps_the_closest(client, db_session, named_gyms, kakao_off):
    import asyncio

    from app.services import gym_search

    gyms = asyncio.run(gym_search.search(db_session, WORD, **SINCHON, limit=1))
    assert [g.id for g in gyms] == [NEAR_ID]

    by_name = asyncio.run(gym_search.search(db_session, WORD, limit=2))
    assert [g.id for g in by_name] == [FAR_ID, NEAR_ID]


# ---- 데모 제외 ----


def test_search_shows_demo_gyms_on_a_demo_server(client, kakao_off):
    assert HEALTHMATE_ID in _ids(_search(client, "헬스메이트"))


def test_search_hides_demo_gyms_when_demo_is_off(client, named_gyms, kakao_off, demo_off):
    from app.db import demo_ids

    assert _ids(_search(client, "헬스메이트")) == []
    # 실재 업체 역할의 헬스장은 그대로 나온다.
    ids = _ids(_search(client, WORD))
    assert ids == [FAR_ID, NEAR_ID, NO_COORDS_ID]
    assert not set(ids) & demo_ids.demo_place_ids()


def test_search_hides_a_demo_gym_kakao_points_at_when_demo_is_off(
    client, fake_kakao, demo_off
):
    """카카오 결과가 가상 헬스장 행을 가리켜도 데모를 끈 서버는 어느 쪽으로도 싣지 않는다."""
    from app.db import demo_ids

    demo_gym_id = "gym-demo-ptlab"
    assert demo_gym_id in demo_ids.demo_place_ids()
    real = _new_kakao_id()
    fake_kakao["docs"] = [
        _kakao_doc(demo_gym_id, "가상 헬스장"),
        _kakao_doc(real, f"{WORD} 실재짐"),
    ]

    assert _ids(_search(client, WORD)) == [real]


def test_search_keeps_a_demo_gym_kakao_points_at_on_a_demo_server(client, fake_kakao):
    demo_gym_id = "gym-demo-ptlab"
    fake_kakao["docs"] = [_kakao_doc(demo_gym_id, "카카오쪽 이름")]

    rows = _rows(_search(client, WORD))
    assert [g["id"] for g in rows] == [demo_gym_id]
    assert rows[0]["name"] != "카카오쪽 이름"  # 등록된 행의 이름


# ---- 요청 제한 ----


def test_search_is_rate_limited_per_member(client, monkeypatch, kakao_off):
    from tests.test_consultations import _auth, _register_member

    monkeypatch.setattr(get_settings(), "rate_limit_enabled", True)
    monkeypatch.setattr(get_settings(), "gym_search_per_minute", 2)
    _, token = _register_member(client)
    _, other = _register_member(client)

    assert client.get(
        "/v1/gyms/search", params={"q": WORD}, headers=_auth(token)
    ).status_code == 200
    assert client.get(
        "/v1/gyms/search", params={"q": WORD}, headers=_auth(token)
    ).status_code == 200
    blocked = client.get("/v1/gyms/search", params={"q": WORD}, headers=_auth(token))
    assert blocked.status_code == 429, blocked.text
    assert blocked.headers.get("Retry-After")

    # 회원 id 로 센다 — 같은 IP 의 다른 회원은 막히지 않는다.
    assert client.get(
        "/v1/gyms/search", params={"q": WORD}, headers=_auth(other)
    ).status_code == 200


def test_search_limit_can_be_turned_off(client, monkeypatch, kakao_off):
    monkeypatch.setattr(get_settings(), "rate_limit_enabled", True)
    monkeypatch.setattr(get_settings(), "gym_search_per_minute", 0)
    for _ in range(5):
        assert _search(client, WORD).status_code == 200


def test_invalid_search_does_not_spend_the_limit(client, monkeypatch, kakao_off):
    """검증에서 떨어진 요청은 외부 호출이 없으므로 세지 않는다."""
    monkeypatch.setattr(get_settings(), "rate_limit_enabled", True)
    monkeypatch.setattr(get_settings(), "gym_search_per_minute", 1)
    assert _search(client, "   ").status_code == 422
    assert _search(client, WORD, lat=37.5).status_code == 422
    assert _search(client, WORD).status_code == 200
