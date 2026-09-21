"""MY 프로필 펫 이모지 — 기간제 꾸밈. (#2021) DB 필요(로컬 skip, CI 실행)."""
from __future__ import annotations

from datetime import timedelta
from uuid import uuid4

from sqlalchemy import select

from app.core import clock
from app.models.models import HealthProfile, ProfilePet
from app.services import profile_pet_service


def _member(client, db_session, points: int) -> dict[str, str]:
    email = f"pet-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    member_id = client.get("/v1/users/me", headers=headers).json()["id"]
    db_session.expire_all()
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    if profile is None:
        db_session.add(HealthProfile(user_id=member_id, activity_points=points))
    else:
        profile.activity_points = points
    db_session.commit()
    return headers


def _buy(client, headers, kind: str):
    return client.post(
        "/v1/me/points/exchange",
        json={"item": "profile_pet", "option": kind},
        headers=headers,
    )


def _shop_card(client, headers) -> dict:
    items = client.get("/v1/me/points/shop", headers=headers).json()["items"]
    return next(i for i in items if i["id"] == "profile_pet")


def test_pet_is_worn_for_seven_days_and_blocks_a_second_buy(client, db_session):
    headers = _member(client, db_session, points=1000)

    assert _buy(client, headers, "fox").status_code == 404
    bought = _buy(client, headers, "dog")
    assert bought.status_code == 201, bought.text
    assert bought.json()["balance"] == 1000 - profile_pet_service.COST

    pet = client.get("/v1/me/profile-pet", headers=headers).json()["pet"]
    assert pet["kind"] == "dog"
    assert 6 * 86400 < pet["remaining_seconds"] <= 7 * 86400
    # 사용처 카드는 막히고 남은 기간을 싣는다.
    card = _shop_card(client, headers)
    assert (card["blocked_reason"], card["active_option"]) == ("active_pet", "dog")
    assert card["remaining_seconds"] > 0
    assert _buy(client, headers, "cat").status_code == 409


def test_pet_falls_off_after_it_expires(client, db_session):
    headers = _member(client, db_session, points=1000)
    _buy(client, headers, "cat")
    db_session.expire_all()
    for row in db_session.scalars(select(ProfilePet)).all():
        row.expires_at = clock.now() - timedelta(seconds=1)
    db_session.commit()

    assert client.get("/v1/me/profile-pet", headers=headers).json()["pet"] is None
    card = _shop_card(client, headers)
    assert card["available"] is True and card["active_option"] is None
