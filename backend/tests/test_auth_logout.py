"""로그아웃 · refresh 토큰 폐기 — DB 필요(로컬 skip, CI 실행).

로그아웃이 로컬 저장소만 지우던 때에는, 새어 나간 refresh 토큰이 남은 수명
(기본 30일) 동안 계속 세션을 되살릴 수 있었다. 여기서 확인하는 것은 **서버가
그 토큰을 실제로 끊는가**다(#966).
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

from app.core.security import decode_refresh_claims
from app.models.models import RevokedRefreshToken
from app.services import token_revocation


def _sign_up(client) -> tuple[str, str]:
    """새 계정을 만들고 (user_id, refresh_token) 을 돌려준다."""
    email = f"logout-{uuid4().hex[:8]}@oncare.com"
    password = "pw-12345!"
    created = client.post(
        "/v1/auth/register",
        json={"email": email, "password": password, "name": "로그아웃"},
    )
    assert created.status_code == 201, created.text
    login = client.post(
        "/v1/auth/login", data={"username": email, "password": password}
    )
    assert login.status_code == 200, login.text
    return created.json()["id"], login.json()["refresh_token"]


def test_logout_revokes_refresh_token(client):
    """로그아웃한 토큰으로는 더 이상 회전할 수 없다."""
    _, refresh_token = _sign_up(client)

    out = client.post("/v1/auth/logout", json={"refresh_token": refresh_token})
    assert out.status_code == 204, out.text

    denied = client.post("/v1/auth/refresh", json={"refresh_token": refresh_token})
    assert denied.status_code == 401


def test_logout_is_idempotent_and_tolerates_garbage(client):
    """두 번 눌러도, 못 알아볼 토큰이어도 204 — 클라이언트가 할 일은 같다."""
    _, refresh_token = _sign_up(client)

    assert (
        client.post("/v1/auth/logout", json={"refresh_token": refresh_token})
    ).status_code == 204
    assert (
        client.post("/v1/auth/logout", json={"refresh_token": refresh_token})
    ).status_code == 204
    assert (
        client.post("/v1/auth/logout", json={"refresh_token": "not-a-token"})
    ).status_code == 204


def test_refresh_token_is_single_use(client):
    """회전에 쓴 토큰은 두 번 쓰이지 않는다 — 두 번째는 재사용으로 거부된다."""
    _, refresh_token = _sign_up(client)

    rotated = client.post("/v1/auth/refresh", json={"refresh_token": refresh_token})
    assert rotated.status_code == 200, rotated.text
    next_refresh = rotated.json()["refresh_token"]
    assert next_refresh and next_refresh != refresh_token

    replayed = client.post("/v1/auth/refresh", json={"refresh_token": refresh_token})
    assert replayed.status_code == 401

    # 회전으로 받은 새 토큰은 멀쩡하다 — 재사용 거부가 정상 세션까지 끊으면 안 된다.
    again = client.post("/v1/auth/refresh", json={"refresh_token": next_refresh})
    assert again.status_code == 200, again.text


def test_refresh_reuse_is_audited(client, db_session):
    """재사용 탐지는 감사 로그에 남는다 — 토큰이 샌 정황을 나중에 볼 수 있어야 한다."""
    from app.models.models import AuditLog

    user_id, refresh_token = _sign_up(client)
    client.post("/v1/auth/refresh", json={"refresh_token": refresh_token})
    client.post("/v1/auth/refresh", json={"refresh_token": refresh_token})

    logged = (
        db_session.query(AuditLog)
        .filter(AuditLog.event == "auth.refresh_reuse", AuditLog.user_id == user_id)
        .all()
    )
    assert len(logged) == 1
    assert logged[0].success is False


def test_logout_after_account_deletion_does_not_fail(client):
    """탈퇴한 계정의 토큰으로 로그아웃해도 204 — 폐기 표는 users 를 참조한다."""
    email = f"gone-{uuid4().hex[:8]}@oncare.com"
    password = "pw-12345!"
    assert (
        client.post(
            "/v1/auth/register",
            json={"email": email, "password": password, "name": "탈퇴"},
        )
    ).status_code == 201
    login = client.post(
        "/v1/auth/login", data={"username": email, "password": password}
    )
    tokens = login.json()
    # 탈퇴는 현재 비밀번호로 본인을 확인한다(#3039).
    deleted = client.request(
        "DELETE",
        "/v1/users/me",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
        json={"current_password": password},
    )
    assert deleted.status_code == 200, deleted.text

    out = client.post(
        "/v1/auth/logout", json={"refresh_token": tokens["refresh_token"]}
    )
    assert out.status_code == 204, out.text
    # 계정이 없으니 회전도 막힌다.
    assert (
        client.post(
            "/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]}
        )
    ).status_code == 401


def test_expired_revocations_are_purged(client, db_session):
    """폐기 표는 무한히 자라지 않는다 — 만료된 항목은 다음 폐기 때 정리된다."""
    user_id, refresh_token = _sign_up(client)
    stale_jti = f"stale-{uuid4().hex[:8]}"
    db_session.add(
        RevokedRefreshToken(
            jti=stale_jti,
            user_id=user_id,
            expires_at=datetime.now(timezone.utc) - timedelta(days=1),
        )
    )
    db_session.commit()

    out = client.post("/v1/auth/logout", json={"refresh_token": refresh_token})
    assert out.status_code == 204

    db_session.expire_all()
    assert db_session.get(RevokedRefreshToken, stale_jti) is None
    # 방금 폐기한 토큰은 아직 만료 전이라 남아 있어야 한다.
    live_jti = decode_refresh_claims(refresh_token).jti
    assert db_session.get(RevokedRefreshToken, live_jti) is not None


def test_purge_expired_keeps_live_entries(client, db_session):
    """정리는 만료된 것만 지운다."""
    user_id, refresh_token = _sign_up(client)
    live_jti = f"live-{uuid4().hex[:8]}"
    db_session.add(
        RevokedRefreshToken(
            jti=live_jti,
            user_id=user_id,
            expires_at=datetime.now(timezone.utc) + timedelta(days=7),
        )
    )
    db_session.commit()

    removed = token_revocation.purge_expired(db_session)
    db_session.commit()

    assert removed == 0
    assert db_session.get(RevokedRefreshToken, live_jti) is not None
    assert token_revocation.is_revoked(db_session, live_jti) is True
    assert token_revocation.is_revoked(db_session, decode_refresh_claims(refresh_token).jti) is False
