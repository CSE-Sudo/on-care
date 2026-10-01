"""보안 유틸(비밀번호 해싱 · JWT) 검증 — DB 불필요."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt
import pytest

from app.core.security import (
    _encode,
    create_access_token,
    create_refresh_token,
    decode_access_token,
    decode_refresh_claims,
    hash_password,
    verify_password,
)


def test_password_hash_roundtrip():
    hashed = hash_password("s3cret!")
    assert hashed and hashed != "s3cret!"
    assert verify_password("s3cret!", hashed) is True
    assert verify_password("wrong-password", hashed) is False


def test_verify_empty_hash_is_false():
    assert verify_password("anything", "") is False


def test_jwt_roundtrip():
    token = create_access_token("user-123")
    assert decode_access_token(token) == "user-123"


def test_jwt_invalid_token_raises():
    with pytest.raises(jwt.InvalidTokenError):
        decode_access_token("not-a-valid-token")


def test_refresh_token_roundtrip():
    token = create_refresh_token("user-9")
    assert decode_refresh_claims(token).subject == "user-9"


def test_access_token_rejected_as_refresh():
    """액세스 토큰을 refresh 로 쓰면 거부."""
    with pytest.raises(jwt.InvalidTokenError):
        decode_refresh_claims(create_access_token("user-9"))


def test_refresh_token_rejected_as_access():
    """refresh 토큰을 액세스로 쓰면 거부(토큰 혼용 방지)."""
    with pytest.raises(jwt.InvalidTokenError):
        decode_access_token(create_refresh_token("user-9"))


def test_refresh_token_carries_unique_jti():
    """폐기하려면 토큰마다 이름이 달라야 한다 — 두 장이 같은 jti 면 한쪽을 끊을 때
    다른 쪽까지 끊긴다(#966)."""
    first = decode_refresh_claims(create_refresh_token("user-9"))
    second = decode_refresh_claims(create_refresh_token("user-9"))
    assert first.jti and second.jti
    assert first.jti != second.jti
    assert first.expires_at > datetime.now(timezone.utc)


def test_refresh_token_without_jti_rejected():
    """#966 이전에 발급된 토큰 — 폐기할 이름이 없어 일회용으로 만들 수 없다."""
    legacy = _encode("user-9", "refresh", timedelta(days=1))
    with pytest.raises(jwt.InvalidTokenError):
        decode_refresh_claims(legacy)


# ---- 토큰 세대(#2766) ----


def test_tokens_carry_the_given_token_version():
    """발급 때 준 세대가 그대로 읽혀야 검증하는 쪽이 계정 세대와 비교할 수 있다."""
    from app.core.security import decode_access_claims

    access = decode_access_claims(create_access_token("user-1", token_version=3))
    assert access.subject == "user-1"
    assert access.token_version == 3
    refresh = decode_refresh_claims(create_refresh_token("user-1", token_version=3))
    assert refresh.token_version == 3


def test_token_version_defaults_to_zero():
    """세대를 주지 않은 발급은 0세대다 — 모든 계정이 0에서 시작한다."""
    from app.core.security import decode_access_claims

    assert decode_access_claims(create_access_token("user-1")).token_version == 0
    assert decode_refresh_claims(create_refresh_token("user-1")).token_version == 0


def test_token_without_version_claim_is_generation_zero():
    """세대 클레임이 생기기 전에 발급된 토큰은 0세대로 읽힌다 — 배포만으로 기존
    세션이 끊기지 않는다."""
    from app.core.config import get_settings
    from app.core.security import decode_access_claims

    s = get_settings()
    now = datetime.now(timezone.utc)
    legacy = jwt.encode(
        {"sub": "user-1", "type": "access", "iat": now, "exp": now + timedelta(minutes=5)},
        s.jwt_secret,
        algorithm=s.jwt_algorithm,
    )
    assert decode_access_claims(legacy).token_version == 0
    assert decode_access_token(legacy) == "user-1"


@pytest.mark.parametrize("bad", ["1", 1.5, True, None, [1]])
def test_malformed_token_version_is_rejected(bad):
    """세대 자리에 정수가 아닌 값이 오면 위조·손상으로 보고 거부한다. `true` 가
    1세대로 통하면 안 된다."""
    from app.core.config import get_settings
    from app.core.security import decode_access_claims

    s = get_settings()
    now = datetime.now(timezone.utc)
    token = jwt.encode(
        {
            "sub": "user-1",
            "type": "access",
            "iat": now,
            "exp": now + timedelta(minutes=5),
            "tv": bad,
        },
        s.jwt_secret,
        algorithm=s.jwt_algorithm,
    )
    with pytest.raises(jwt.InvalidTokenError):
        decode_access_claims(token)
