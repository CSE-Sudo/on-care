"""토큰 세대 도우미(#2766) — DB 불필요."""
from __future__ import annotations

from app.core.security import decode_access_claims, decode_refresh_claims
from app.models.models import User
from app.services import auth_tokens


def _user(version: int | None) -> User:
    return User(id="user-tv", email="tv@example.invalid", token_version=version)


def test_new_unflushed_user_counts_as_generation_zero():
    """flush 전 새 객체는 칸이 비어 있다 — 0세대로 보고 발급해야 가입 직후 토큰이 산다."""
    assert auth_tokens.current_version(_user(None)) == 0
    assert auth_tokens.is_current(_user(None), 0)


def test_issued_pair_carries_the_current_generation():
    pair = auth_tokens.issue_token_pair(_user(4))
    assert decode_access_claims(pair.access_token).token_version == 4
    assert decode_refresh_claims(pair.refresh_token).token_version == 4
    assert pair.token_type == "bearer"


def test_bump_makes_previous_tokens_stale():
    user = _user(0)
    before = decode_access_claims(auth_tokens.issue_token_pair(user).access_token)
    auth_tokens.bump_version(user)
    assert user.token_version == 1
    assert not auth_tokens.is_current(user, before.token_version)
    after = decode_access_claims(auth_tokens.issue_token_pair(user).access_token)
    assert auth_tokens.is_current(user, after.token_version)


def test_bump_from_unset_starts_at_one():
    user = _user(None)
    auth_tokens.bump_version(user)
    assert user.token_version == 1
