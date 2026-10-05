"""트레이너 가입. (#475, #1627)

트레이너 계정을 만들 방법이 시드 스크립트뿐이었다. 가입한 계정이 실제로
트레이너로 동작하는지(= `/trainer/me` 가 200 을 주는지)를 확인한다 —
`users.role` 만 보면 "가입은 됐는데 아무것도 못 하는" 상태를 놓친다.

소속 헬스장은 가입 때 정하지 않는다(#1627). 가입 직후에는 소속이 비어 있고,
`PUT /trainer/me/gym` 으로 고른다.

DB 가 필요하므로 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest

from app.models.models import Place, TrainerProfile, User

EMAIL_PREFIX = "signup-test-"
PLACE_PREFIX = "signup-place-"
PASSWORD = "signup-pw-1234"


@pytest.fixture(autouse=True)
def _cleanup(db_session):
    yield
    db_session.rollback()
    user_ids = [
        row[0]
        for row in db_session.query(User.id)
        .filter(User.email.like(f"{EMAIL_PREFIX}%"))
        .all()
    ]
    if user_ids:
        db_session.query(TrainerProfile).filter(
            TrainerProfile.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(User).filter(User.id.in_(user_ids)).delete(
            synchronize_session=False
        )
    db_session.query(Place).filter(Place.id.like(f"{PLACE_PREFIX}%")).delete(
        synchronize_session=False
    )
    db_session.commit()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _gym(db_session) -> Place:
    place = Place(
        id=f"{PLACE_PREFIX}{uuid4().hex[:10]}",
        name="가입 테스트 헬스장",
        category="fitness",
        address="서울",
    )
    db_session.add(place)
    db_session.commit()
    return place


def _payload(*, email: str | None = None) -> dict:
    return {
        "email": email or f"{EMAIL_PREFIX}{uuid4().hex[:10]}@oncare.com",
        "password": PASSWORD,
        "name": "신규 트레이너",
    }


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def test_signup_creates_a_working_trainer_without_a_gym(client):
    """가입한 계정이 실제로 트레이너로 동작하고, 소속은 비어 있다."""
    payload = _payload()

    response = client.post("/v1/auth/trainer/register", json=payload)

    assert response.status_code == 201, response.text
    assert response.json()["email"] == payload["email"]

    # role 만 보지 않는다 — 트레이너 앱이 처음 부르는 엔드포인트로 확인한다.
    me = client.get("/v1/trainer/me", headers=_auth(_login(client, payload["email"])))
    assert me.status_code == 200, me.text
    assert me.json()["gym"]["id"] is None
    # 운영자 승인 단계는 없다(#3008) — 응답에 승인 상태가 없다.
    assert "verification" not in me.json()


def test_a_signed_up_trainer_can_pick_a_gym(client, db_session):
    """가입 뒤 소속을 고르는 길이 이어져 있다 — 초대 코드가 하던 일을 대신한다."""
    gym = _gym(db_session)
    payload = _payload()
    client.post("/v1/auth/trainer/register", json=payload)
    token = _login(client, payload["email"])

    picked = client.put(
        "/v1/trainer/me/gym", headers=_auth(token), json={"gym_id": gym.id}
    )

    assert picked.status_code == 200, picked.text
    assert picked.json()["gym"]["id"] == gym.id


def test_signup_ignores_a_leftover_invite_code(client):
    """예전 앱이 초대 코드를 실어 보내도 가입을 막지 않는다."""
    payload = {**_payload(), "invite_code": "OLDAPP1"}

    response = client.post("/v1/auth/trainer/register", json=payload)

    assert response.status_code == 201, response.text


def test_duplicate_email_conflicts(client):
    taken = f"{EMAIL_PREFIX}{uuid4().hex[:10]}@oncare.com"
    client.post("/v1/auth/register", json={
        "email": taken, "password": PASSWORD, "name": "회원",
    })

    response = client.post(
        "/v1/auth/trainer/register", json=_payload(email=taken)
    )

    assert response.status_code == 409, response.text


def test_member_register_still_creates_a_member(client):
    """회원 가입 경로는 그대로다 — 트레이너가 되지 않는다."""
    email = f"{EMAIL_PREFIX}{uuid4().hex[:10]}@oncare.com"
    created = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": "회원"},
    )
    assert created.status_code == 201, created.text

    me = client.get("/v1/trainer/me", headers=_auth(_login(client, email)))

    # 회원 계정은 트레이너 엔드포인트에서 403 이어야 한다.
    assert me.status_code == 403, me.text
