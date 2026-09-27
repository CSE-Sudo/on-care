"""인증(회원가입 · 로그인 · 토큰) — DB 필요(로컬 skip, CI 실행)."""
from __future__ import annotations

from uuid import uuid4


def test_register_login_and_me(client):
    email = f"tester-{uuid4().hex[:8]}@oncare.com"
    password = "pw-12345!"

    r = client.post(
        "/v1/auth/register",
        json={"email": email, "password": password, "name": "테스터"},
    )
    assert r.status_code == 201, r.text
    user_id = r.json()["id"]

    r2 = client.post("/v1/auth/login", data={"username": email, "password": password})
    assert r2.status_code == 200, r2.text
    token = r2.json()["access_token"]
    assert token

    # 발급 토큰으로 인증된 /users/me 는 가입한 사용자를 반환해야 한다
    r3 = client.get("/v1/users/me", headers={"Authorization": f"Bearer {token}"})
    assert r3.status_code == 200
    assert r3.json()["id"] == user_id


def test_login_wrong_password_401(client):
    email = f"tester-{uuid4().hex[:8]}@oncare.com"
    client.post("/v1/auth/register", json={"email": email, "password": "correct-pw-1", "name": "x"})
    r = client.post("/v1/auth/login", data={"username": email, "password": "wrong-pw"})
    assert r.status_code == 401


def test_inactive_user_cannot_login_or_use_existing_access_token(client, db_session):
    """비활성화된 계정은 새 로그인과 기존 access token 사용이 모두 차단되어야 한다."""
    from app.models.models import User

    email = f"inactive-{uuid4().hex[:8]}@oncare.com"
    password = "pw-12345!"
    registered = client.post(
        "/v1/auth/register",
        json={"email": email, "password": password, "name": "비활성회원"},
    )
    assert registered.status_code == 201
    login = client.post(
        "/v1/auth/login", data={"username": email, "password": password}
    )
    assert login.status_code == 200
    token = login.json()["access_token"]

    user = db_session.get(User, registered.json()["id"])
    assert user is not None
    user.is_active = False
    db_session.commit()

    assert client.post(
        "/v1/auth/login", data={"username": email, "password": password}
    ).status_code == 401
    assert client.get(
        "/v1/users/me",
        headers={"Authorization": f"Bearer {token}"},
    ).status_code == 401


def test_duplicate_register_conflicts_409(client):
    email = f"dup-{uuid4().hex[:8]}@oncare.com"
    r1 = client.post("/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "a"})
    assert r1.status_code == 201
    r2 = client.post("/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "a"})
    assert r2.status_code == 409


def test_refresh_token_flow(client):
    email = f"ref-{uuid4().hex[:8]}@oncare.com"
    client.post("/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "r"})
    login = client.post("/v1/auth/login", data={"username": email, "password": "test-pw-1234"})
    assert login.status_code == 200
    refresh_token = login.json()["refresh_token"]
    assert refresh_token

    # refresh 로 새 access 발급 → /users/me 동작
    r = client.post("/v1/auth/refresh", json={"refresh_token": refresh_token})
    assert r.status_code == 200, r.text
    new_access = r.json()["access_token"]
    me = client.get("/v1/users/me", headers={"Authorization": f"Bearer {new_access}"})
    assert me.status_code == 200

    # 잘못된 refresh → 401
    bad = client.post("/v1/auth/refresh", json={"refresh_token": "not-a-token"})
    assert bad.status_code == 401
