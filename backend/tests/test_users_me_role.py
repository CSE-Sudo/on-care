"""`GET /users/me` 와 가입 응답의 계정 역할(`role`). (#3054)

회원 앱과 트레이너 웹은 한 출처에 배포돼 브라우저 저장소를 같이 쓴다. 회원 앱은
세션을 되살릴 때 `role` 로 자기 계정인지 한 번 더 확인한다.

앞부분은 DB 없이 도는 스키마 검사, 뒤의 엔드포인트 검사는 `client` 픽스처를
쓰므로 DB 가 있는 환경(CI)에서 돈다.
"""
from __future__ import annotations

from uuid import uuid4

from app.schemas.user import UserMe

PASSWORD = "role-pw-1234"


# ---- 스키마 (DB 불필요) ----


def test_user_me_role_defaults_to_member():
    me = UserMe(id="u1", name="회원", email="m@oncare.com")
    assert me.role == "member"
    assert me.model_dump()["role"] == "member"


def test_user_me_carries_trainer_role():
    me = UserMe(id="t1", name="트레이너", email="t@oncare.com", role="trainer")
    assert me.model_dump()["role"] == "trainer"


# ---- 엔드포인트 (DB 필요) ----


def _email(tag: str) -> str:
    return f"role-{tag}-{uuid4().hex[:8]}@oncare.com"


def _login(client, email: str) -> str:
    return client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    ).json()["access_token"]


def test_member_me_reports_member_role(client):
    email = _email("member")
    created = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": "회원"},
    )
    assert created.status_code == 201
    assert created.json()["role"] == "member"

    token = _login(client, email)
    res = client.get("/v1/users/me", headers={"Authorization": f"Bearer {token}"})
    assert res.status_code == 200
    assert res.json()["role"] == "member"


def test_trainer_register_reports_trainer_role(client):
    created = client.post(
        "/v1/auth/trainer/register",
        json={"email": _email("trainer"), "password": PASSWORD, "name": "트레이너"},
    )
    assert created.status_code == 201
    assert created.json()["role"] == "trainer"


def test_trainer_token_still_forbidden_on_member_me(client):
    email = _email("trainer-me")
    client.post(
        "/v1/auth/trainer/register",
        json={"email": email, "password": PASSWORD, "name": "트레이너"},
    )
    token = _login(client, email)
    res = client.get("/v1/users/me", headers={"Authorization": f"Bearer {token}"})
    # 역할 칸이 생겨도 트레이너 토큰은 회원 API 에서 거절된다 — 역할이 새어
    # 나가 회원 앱이 트레이너 계정을 받아들이는 길이 없다.
    assert res.status_code == 403
    assert "role" not in res.json()
