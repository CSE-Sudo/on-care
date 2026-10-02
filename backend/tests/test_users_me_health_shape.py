"""`GET /users/me/health` 응답 모양. (#2903)

앱이 읽지 않는 위험 문구(`risk`)·활동 순위(`activity_rank`)·설정 메뉴
(`settings`)를 고정값으로 채워 보내던 것을 뺐다. 회원 앱 MY 카드가 쓰는 것은
프로필과 포인트 잔액뿐이다. 데모 응답(`local_api_interceptor.dart`)도 같은 모양이다.

스키마 검사는 DB 없이, 실제 응답 검사는 DB 가 있을 때(CI) 돈다.
"""
from __future__ import annotations

from uuid import uuid4

from sqlalchemy import select

from app.schemas.user import UserHealth

_REMOVED = ("risk", "activity_rank", "settings")


def test_response_schema_carries_only_profile_and_points():
    assert set(UserHealth.model_fields) == {"profile", "activity_points"}


def _register(client) -> dict[str, str]:
    email = f"health-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register",
        json={"email": email, "password": "test-pw-1234", "name": "u"},
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def test_member_without_risk_copy_gets_no_fixed_rank(client):
    """위험 문구 없는 회원 — 예전에는 고정 순위 14 와 고정 문구가 실렸다."""
    h = _register(client)
    r = client.get("/v1/users/me/health", headers=h)
    assert r.status_code == 200, r.text
    body = r.json()
    assert set(body) == {"profile", "activity_points"}
    assert body["activity_points"] == 0
    assert set(body["profile"]) == {"id", "name", "email"}


def test_stored_risk_and_rank_are_not_exposed(client, db_session):
    """프로필에 위험 문구·순위가 저장돼 있어도 응답에는 싣지 않는다."""
    from app.models.models import HealthProfile

    h = _register(client)
    member_id = client.get("/v1/users/me", headers=h).json()["id"]
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    if profile is None:
        # 가입만 한 회원은 프로필 행이 아직 없을 수 있다.
        profile = HealthProfile(user_id=member_id)
        db_session.add(profile)
    profile.risk_title = "주의"
    profile.risk_body = "관리 필요"
    profile.activity_rank = 3
    db_session.commit()

    body = client.get("/v1/users/me/health", headers=h).json()
    for key in _REMOVED:
        assert key not in body, key
    assert body["profile"]["id"] == member_id
