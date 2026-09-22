"""사진 없이 직접 적은 끼니(POST /diet/entries). (#2151) DB 필요(로컬 skip, CI 실행).

새로 가입한 회원으로 확인해 다른 테스트가 만든 기록·적립과 섞이지 않게 한다.
"""
from __future__ import annotations

import json
from datetime import timedelta
from uuid import uuid4

import pytest

from app.core import clock


def _register(client) -> dict[str, str]:
    email = f"manual-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


_FOODS = [
    {"name": "김밥", "amount_g": 230, "calories": 420, "carbs_g": 70,
     "protein_g": 12, "fat_g": 9, "sodium_mg": 900, "sugar_g": 4, "source": "db"},
    {"name": "라면", "calories": 500, "carbs_g": 80, "protein_g": 10,
     "fat_g": 16, "sodium_mg": 1800, "sugar_g": 3},
]


def _create(client, headers, **overrides):
    body = {"meal_type": "lunch", "foods": _FOODS, **overrides}
    return client.post("/v1/diet/entries", json=body, headers=headers)


def test_manual_entry_is_saved_and_totals_come_from_foods(client):
    h = _register(client)
    r = _create(client, h)
    assert r.status_code == 201, r.text
    entry = r.json()
    assert entry["meal_type"] == "lunch"
    assert [f["name"] for f in entry["foods"]] == ["김밥", "라면"]
    assert entry["total_calories"] == 920
    assert entry["carbs_g"] == 150
    assert entry["sodium_mg"] == 2700
    # 사진이 없는 기록이다 — 사진 경로도, 사진이 만든 식단평도 없다.
    assert entry["photo_url"] is None
    assert entry["ai_comment"] == ""

    today = client.get("/v1/diet/days/today", headers=h).json()
    assert [e["id"] for e in today["entries"]] == [entry["id"]]
    assert today["total_calories"] == 920


def test_manual_entry_keeps_each_food_source(client):
    h = _register(client)
    foods = _create(client, h).json()["foods"]
    # 공공 DB 로 채운 줄은 db, 출처 없이 온 줄은 회원 값이다(#2105).
    assert [f["source"] for f in foods] == ["db", "member"]


def test_manual_entry_earns_no_points(client):
    h = _register(client)
    assert _create(client, h).status_code == 201
    health = client.get("/v1/users/me/health", headers=h).json()
    assert health["activity_points"] == 0


def test_manual_entry_can_be_placed_on_a_past_day(client):
    h = _register(client)
    yesterday = (clock.today() - timedelta(days=1)).isoformat()
    entry_id = _create(client, h, date=yesterday).json()["id"]

    day = client.get(f"/v1/diet/days/{yesterday}", headers=h).json()
    assert [e["id"] for e in day["entries"]] == [entry_id]
    assert client.get("/v1/diet/days/today", headers=h).json()["entries"] == []


def test_manual_entry_rejects_a_future_day(client):
    h = _register(client)
    tomorrow = (clock.today() + timedelta(days=1)).isoformat()
    assert _create(client, h, date=tomorrow).status_code == 422


@pytest.mark.parametrize(
    "overrides",
    [
        {"foods": []},
        {"foods": [{"name": "  ", "calories": 100}]},
        {"meal_type": "brunch"},
    ],
)
def test_manual_entry_rejects_invalid_body(client, overrides):
    h = _register(client)
    assert _create(client, h, **overrides).status_code == 422


def test_manual_entry_rejects_sugar_above_carbs(client):
    """회원이 적은 값이라 탄수화물 0 도 적은 값이다(#1893)."""
    h = _register(client)
    r = _create(
        client, h, foods=[{"name": "사탕", "calories": 40, "carbs_g": 0, "sugar_g": 9}]
    )
    assert r.status_code == 422
    assert "사탕" in r.json()["detail"]


def test_manual_entry_idempotency_key_dedupes_retry(client):
    h = _register(client)
    key = uuid4().hex
    first = _create(client, h, idempotency_key=key)
    second = _create(client, h, idempotency_key=key)
    assert first.status_code == 201 and second.status_code == 201
    assert first.json()["id"] == second.json()["id"]
    assert len(client.get("/v1/diet/days/today", headers=h).json()["entries"]) == 1


def test_manual_entry_can_be_edited_and_deleted(client):
    h = _register(client)
    entry_id = _create(client, h).json()["id"]

    r = client.put(
        f"/v1/diet/entries/{entry_id}", json={"meal_type": "dinner"}, headers=h
    )
    assert r.status_code == 200, r.text
    assert r.json()["meal_type"] == "dinner"

    assert client.delete(f"/v1/diet/entries/{entry_id}", headers=h).status_code == 200
    assert client.get("/v1/diet/days/today", headers=h).json()["entries"] == []


def test_manual_entry_is_stored_with_the_manual_engine(client, db_session):
    from app.models.models import DietEntry

    h = _register(client)
    entry_id = _create(client, h).json()["id"]
    row = db_session.get(DietEntry, entry_id)
    assert row.engine == "manual"
    assert [f["name"] for f in json.loads(row.foods_json)] == ["김밥", "라면"]
