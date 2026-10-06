"""로그인·소셜 로그인 응답의 계정 역할. (#3137)

회원 앱은 받은 토큰을 저장하기 전에 응답의 `role` 을 보고, 트레이너 계정이면
토큰을 버리고 트레이너 웹 안내를 보인다. 그 판단의 근거가 이 칸이다 — 없으면
앱이 지금처럼 들여보내고, 트레이너 토큰으로 회원 API 가 전부 403 이 된다.
"""
from __future__ import annotations

from uuid import uuid4

from app.services.social.base import SocialIdentity


def test_member_login_reports_member_role(client):
    email = f"role-{uuid4().hex[:8]}@oncare.com"
    password = "pw-12345!"
    r = client.post(
        "/v1/auth/register",
        json={"email": email, "password": password, "name": "회원"},
    )
    assert r.status_code == 201, r.text

    r = client.post("/v1/auth/login", data={"username": email, "password": password})
    assert r.status_code == 200, r.text
    assert r.json()["role"] == "member"


def test_trainer_login_reports_trainer_role(client):
    r = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["role"] == "trainer"
    # 역할을 알리는 것이지 토큰을 막는 것은 아니다 — 트레이너 웹도 이 경로를 쓴다.
    assert body["access_token"] and body["refresh_token"]


def test_social_login_reports_account_role(client, db_session, monkeypatch):
    import app.api.v1.social as social_mod
    from app.models.models import User

    email = f"role-soc-{uuid4().hex[:8]}@oncare.com"
    identity = SocialIdentity(
        provider="kakao",
        provider_user_id=f"kakao-{uuid4().hex[:8]}",
        email=email,
        name="소셜",
        # 확인된 이메일이어야 그 주소로 계정이 생긴다(#1551) — 아래에서 이메일로 계정을 찾는다.
        email_verified=True,
    )

    class _FakeVerifier:
        async def verify(self, token):  # noqa: ARG002
            return identity

    monkeypatch.setattr(social_mod, "get_verifier", lambda provider: _FakeVerifier())

    first = client.post("/v1/auth/social/kakao", json={"token": "any"})
    assert first.status_code == 200, first.text
    assert first.json()["role"] == "member"

    # 같은 신원이 트레이너 계정이면 응답도 트레이너라고 알린다.
    user = db_session.query(User).filter(User.email == email).one()
    user.role = "trainer"
    db_session.commit()

    again = client.post("/v1/auth/social/kakao", json={"token": "any"})
    assert again.status_code == 200, again.text
    assert again.json()["role"] == "trainer"


def test_login_token_schema_defaults_to_member():
    from app.schemas.user import LoginToken

    assert LoginToken(access_token="a").role == "member"
