"""헬스장 목록의 범위 제한·데모 제외·단건 조회. (#3356)

`GET /gyms` 는 좌표가 있으면 기본 반경 안에서 가까운 순으로 상한까지만 준다. 데모
시드가 꺼진 서버는 가상 헬스장을 목록·단건·내 헬스장 어디에도 내지 않는다.
"""
from __future__ import annotations

import pytest

from app.core.config import get_settings

SINCHON = {"lat": 37.5559, "lng": 126.9368}
SEEDED_GYM_IDS = {
    "gym-oncare-sinchon", "gym-healthmate", "gym-bodyandsoul",
    "gym-demo-fitstudio", "gym-demo-movelab", "gym-demo-ptlab", "gym-demo-onestudio",
}
#: 데모 장소 시드의 fitness 두 곳 — 신촌에서 3km 를 조금 넘는다.
SEEDED_FITNESS_PLACE_IDS = {"place-2", "place-5"}

FAR_ID = "gym-scope-test-busan"
NEAR_ID = "gym-scope-test-near"
NO_COORDS_ID = "gym-scope-test-no-coords"


@pytest.fixture
def demo_off(monkeypatch):
    """데모 시드가 꺼진 서버(운영과 같은 조건)."""
    monkeypatch.setattr(get_settings(), "seed_demo_data", False)


@pytest.fixture
def extra_gyms(db_session):
    """실재 업체 역할의 헬스장 세 곳 — 부산(반경 밖), 신촌 옆(반경 안), 좌표 없음."""
    from app.models.models import Place

    rows = [
        Place(
            id=FAR_ID, name="범위테스트 부산짐", category="fitness",
            address="부산 해운대구", lat=35.1631, lng=129.1636,
        ),
        Place(
            id=NEAR_ID, name="범위테스트 신촌짐", category="fitness",
            address="서울 서대문구", lat=37.5562, lng=126.9370,
        ),
        Place(
            id=NO_COORDS_ID, name="범위테스트 좌표없는짐", category="fitness",
            address="주소 미상",
        ),
    ]
    db_session.add_all(rows)
    db_session.commit()
    yield
    db_session.query(Place).filter(
        Place.id.in_([FAR_ID, NEAR_ID, NO_COORDS_ID])
    ).delete(synchronize_session=False)
    db_session.commit()


def _ids(response) -> list[str]:
    assert response.status_code == 200, response.text
    return [g["id"] for g in response.json()]


# ---- 반경 ----


def test_default_radius_drops_a_far_gym(client, extra_gyms):
    ids = _ids(client.get("/v1/gyms", params=SINCHON))
    assert NEAR_ID in ids
    assert FAR_ID not in ids


def test_every_listed_gym_is_inside_the_default_radius(client, extra_gyms):
    from app.services import gym_service

    gyms = client.get("/v1/gyms", params=SINCHON).json()
    assert gyms
    assert all(
        g["distance_km"] * 1000 <= gym_service.DEFAULT_GYM_RADIUS_M for g in gyms
    )


def test_wider_radius_brings_the_far_gym_back(client, extra_gyms):
    # 부산은 최대 반경(20km)으로도 닿지 않는다 — 부산 근처에서 물어야 나온다.
    assert FAR_ID not in _ids(
        client.get("/v1/gyms", params={**SINCHON, "radius_m": 20000})
    )
    busan = {"lat": 35.16, "lng": 129.16}
    assert _ids(client.get("/v1/gyms", params=busan)) == [FAR_ID]


def test_narrow_radius_keeps_only_the_closest(client, extra_gyms):
    ids = _ids(client.get("/v1/gyms", params={**SINCHON, "radius_m": 100}))
    assert "gym-oncare-sinchon" in ids
    assert NEAR_ID in ids
    assert "gym-bodyandsoul" not in ids


def test_gym_without_coordinates_is_not_nearby(client, extra_gyms):
    """반경 안인지 알 수 없는 헬스장은 '내 주변' 에 넣지 않는다."""
    assert NO_COORDS_ID not in _ids(client.get("/v1/gyms", params=SINCHON))


def test_list_without_coordinates_is_unchanged(client, extra_gyms):
    """기준점이 없으면 반경도 상한도 걸지 않는다 — 전부 이름순."""
    r = client.get("/v1/gyms", params={"radius_m": 100, "limit": 1})
    ids = _ids(r)
    assert {FAR_ID, NEAR_ID, NO_COORDS_ID} <= set(ids)
    names = [g["name"] for g in r.json()]
    assert names == sorted(names)


# ---- 상한 ----


def test_limit_keeps_the_nearest(client, extra_gyms):
    everything = _ids(client.get("/v1/gyms", params=SINCHON))
    assert len(everything) > 2
    assert _ids(client.get("/v1/gyms", params={**SINCHON, "limit": 2})) == everything[:2]


def test_default_limit_caps_the_list(client, db_session):
    from app.models.models import Place
    from app.services import gym_service

    count = gym_service.DEFAULT_GYM_LIMIT + 5
    ids = [f"gym-scope-bulk-{i:03d}" for i in range(count)]
    db_session.add_all(
        Place(
            id=gym_id, name=f"범위테스트 묶음 {i:03d}", category="fitness",
            address="서울 서대문구", lat=37.5559, lng=126.9368,
        )
        for i, gym_id in enumerate(ids)
    )
    db_session.commit()
    try:
        gyms = client.get("/v1/gyms", params=SINCHON).json()
        assert len(gyms) == gym_service.DEFAULT_GYM_LIMIT
        distances = [g["distance_km"] for g in gyms]
        assert distances == sorted(distances)
    finally:
        db_session.query(Place).filter(Place.id.in_(ids)).delete(
            synchronize_session=False
        )
        db_session.commit()


@pytest.mark.parametrize(
    "params",
    [{"radius_m": 99}, {"radius_m": 20001}, {"limit": 0}, {"limit": 101}],
)
def test_scope_arguments_are_validated(client, params):
    assert client.get("/v1/gyms", params={**SINCHON, **params}).status_code == 422


# ---- 단건 ----


def test_detail_opens_for_a_gym_outside_the_list(client, extra_gyms):
    assert FAR_ID not in _ids(client.get("/v1/gyms", params=SINCHON))
    r = client.get(f"/v1/gyms/{FAR_ID}", params=SINCHON)
    assert r.status_code == 200, r.text
    assert r.json()["id"] == FAR_ID
    assert r.json()["distance_km"] > 300
    assert client.get(f"/v1/gyms/{NO_COORDS_ID}").status_code == 200


def test_my_gym_outside_the_radius_is_still_served(client, db_session, extra_gyms):
    """소속 헬스장은 반경과 무관하다 — `/me/gym` 은 목록을 거치지 않는다."""
    from app.models import models
    from tests.test_consultations import _auth, _register_member

    member_id, token = _register_member(client)
    db_session.add(models.MemberGym(member_id=member_id, gym_id=FAR_ID))
    db_session.commit()
    try:
        r = client.get("/v1/me/gym", headers=_auth(token), params=SINCHON)
        assert r.status_code == 200, r.text
        assert r.json()["id"] == FAR_ID
    finally:
        db_session.query(models.MemberGym).filter_by(member_id=member_id).delete()
        db_session.commit()


# ---- 데모 서버: 그대로 ----


def test_demo_server_list_keeps_every_seeded_gym(client):
    """데모 서버는 신촌 기준으로 지금 보이던 헬스장을 모두 그대로 보여 준다."""
    from app.db import demo_ids

    if not demo_ids.demo_data_enabled():
        pytest.skip("데모 시드가 꺼진 서버")
    ids = set(_ids(client.get("/v1/gyms", params=SINCHON)))
    assert SEEDED_GYM_IDS <= ids
    assert SEEDED_FITNESS_PLACE_IDS <= ids


def test_demo_server_serves_demo_gym_detail(client):
    from app.db import demo_ids

    if not demo_ids.demo_data_enabled():
        pytest.skip("데모 시드가 꺼진 서버")
    assert client.get("/v1/gyms/gym-oncare-sinchon").status_code == 200
    assert client.get("/v1/gyms/gym-oncare-sinchon/trainers").status_code == 200


# ---- 데모가 꺼진 서버: 가상 헬스장 제외 ----


def test_list_hides_demo_gyms_when_demo_is_off(client, extra_gyms, demo_off):
    from app.db import demo_ids

    demo = demo_ids.demo_place_ids()
    assert SEEDED_GYM_IDS | SEEDED_FITNESS_PLACE_IDS <= demo

    nearby = set(_ids(client.get("/v1/gyms", params=SINCHON)))
    assert not nearby & demo
    # 실재 업체는 그대로 나온다.
    assert NEAR_ID in nearby

    everything = set(_ids(client.get("/v1/gyms")))
    assert not everything & demo
    assert {FAR_ID, NEAR_ID, NO_COORDS_ID} <= everything


def test_partner_only_hides_demo_gyms_when_demo_is_off(client, demo_off):
    from app.db import demo_ids

    partners = set(_ids(client.get("/v1/gyms", params={"partner_only": True})))
    assert not partners & demo_ids.demo_place_ids()


def test_detail_is_404_for_a_demo_gym_when_demo_is_off(client, extra_gyms, demo_off):
    assert client.get("/v1/gyms/gym-oncare-sinchon").status_code == 404
    assert client.get("/v1/gyms/gym-oncare-sinchon/trainers").status_code == 404
    assert client.get(f"/v1/gyms/{NEAR_ID}").status_code == 200


def test_my_gym_is_404_for_a_demo_gym_when_demo_is_off(client, db_session, monkeypatch):
    """예전 시드로 가상 헬스장에 묶인 회원에게도 그 헬스장을 내지 않는다."""
    from app.models import models
    from tests.test_consultations import _auth, _register_member

    member_id, token = _register_member(client)
    db_session.add(models.MemberGym(member_id=member_id, gym_id="gym-oncare-sinchon"))
    db_session.commit()
    try:
        assert client.get("/v1/me/gym", headers=_auth(token)).status_code == 200
        monkeypatch.setattr(get_settings(), "seed_demo_data", False)
        assert client.get("/v1/me/gym", headers=_auth(token)).status_code == 404
    finally:
        db_session.query(models.MemberGym).filter_by(member_id=member_id).delete()
        db_session.commit()


# ---- 서비스 ----


def test_service_orders_by_distance_then_name(client, db_session, extra_gyms):
    from app.services import gym_service

    gyms = gym_service.list_gyms(db_session, **SINCHON)
    keys = [(g.distance_km, g.name) for g in gyms]
    assert keys == sorted(keys)
    assert gyms[0].id == "gym-oncare-sinchon"


def test_service_radius_is_inclusive_at_the_boundary(client, db_session, extra_gyms):
    from app.services import gym_service

    near = gym_service.get_gym(db_session, NEAR_ID, **SINCHON)
    meters = round(near.distance_km * 1000)
    inside = gym_service.list_gyms(db_session, **SINCHON, radius_m=meters)
    outside = gym_service.list_gyms(db_session, **SINCHON, radius_m=meters - 1)
    assert NEAR_ID in {g.id for g in inside}
    assert NEAR_ID not in {g.id for g in outside}


def test_service_get_gym_ignores_the_radius(client, db_session, extra_gyms):
    from app.services import gym_service

    assert gym_service.get_gym(db_session, FAR_ID, **SINCHON) is not None
    assert gym_service.get_gym(db_session, "gym-does-not-exist") is None
