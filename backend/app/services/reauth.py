"""민감한 계정 변경 전 본인 확인(#3039).

탈퇴와 로그인 이메일 변경은 예전에 접근 토큰만 보고 처리했다. 토큰이 새거나, 잠금
없는 휴대폰을 남이 들면 그 사람이 계정을 지우거나 이메일을 자기 주소로 바꿔
(비밀번호 재설정 메일까지 받아) 계정을 가져갈 수 있었다. 이제 두 동작은 본인 확인을
한 번 더 거친다.

- 비밀번호가 있는 계정: 현재 비밀번호.
- 소셜 로그인 전용 계정(비밀번호 없음): 방금 그 provider 로 다시 로그인해 받은 토큰.
  provider 검증기로 확인하고, 그 provider 계정이 **이 사용자에게 연결된** 것이어야
  한다 — 남의 소셜 토큰으로는 안 된다.

실패는 모두 400 이다(`{code, message}`). 토큰은 유효하므로 앱이 로그아웃으로 오인하면
안 된다(비밀번호 변경과 같은 규약). 연속 실패는 사용자 id 단위로 잠근다
(`PASSWORD_CHANGE_MAX_FAILURES` 번, `LOGIN_LOCKOUT_SECONDS` 동안 429) — 접근 토큰을
손에 넣은 쪽이 비밀번호를 맞혀 보는 것을 막는다. 실패는 감사 로그에 남는다.
"""
from __future__ import annotations

import asyncio
import logging
from collections.abc import Awaitable, Callable
from typing import TypeVar

import anyio.from_thread
from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.rate_limit import claim_attempt, clear_failures, ensure_unlocked
from app.core.security import verify_password
from app.models.models import SocialAccount, User
from app.services import audit
from app.services.social.base import SocialIdentity
from app.services.social.factory import get_verifier

log = logging.getLogger(__name__)

T = TypeVar("T")

#: 확인 값을 보내지 않았다.
REAUTH_REQUIRED = {
    "code": "reauth_required",
    "message": "본인 확인을 위해 현재 비밀번호를 입력해 주세요.",
}
#: 소셜 로그인 전용 계정이 확인 값을 보내지 않았다(코드는 같다).
REAUTH_REQUIRED_SOCIAL = {
    "code": "reauth_required",
    "message": "본인 확인을 위해 소셜 계정으로 다시 로그인해 주세요.",
}
INVALID_CURRENT_PASSWORD = {
    "code": "invalid_current_password",
    "message": "현재 비밀번호가 일치하지 않습니다.",
}
INVALID_REAUTH = {
    "code": "invalid_reauth",
    "message": "소셜 계정 확인에 실패했습니다. 다시 로그인해 주세요.",
}

#: 확인하는 동작. 감사 로그 `detail` 의 `action=` 이다.
DELETE_ACCOUNT = "delete_account"
CHANGE_EMAIL = "change_email"


def fail_key(user_id: str) -> str:
    """연속 실패 잠금 버킷 키. 비밀번호 변경 잠금과 따로 센다."""
    return f"reauth-fail:{user_id}"


def _run_async(fn: Callable[[str], Awaitable[T]], arg: str) -> T:
    """동기 핸들러(스레드풀)에서 provider 검증 코루틴을 돌린다.

    FastAPI 는 동기 핸들러를 AnyIO 작업 스레드에서 부르므로 그 이벤트 루프로 넘긴다.
    작업 스레드가 아니면(스크립트·단위 테스트) 새 루프를 연다.
    """
    try:
        return anyio.from_thread.run(fn, arg)
    except RuntimeError:
        return asyncio.run(fn(arg))  # type: ignore[arg-type]


def _verify_social(provider: str, token: str) -> SocialIdentity | None:
    """provider 토큰을 검증한다. 어떤 이유로든 실패하면 None(까닭은 로그에만)."""
    try:
        verifier = get_verifier(provider)
        return _run_async(verifier.verify, token)
    except Exception as exc:  # noqa: BLE001 — 실패 종류는 응답에 드러내지 않는다
        log.info("본인 확인 소셜 검증 실패 provider=%s type=%s", provider, type(exc).__name__)
        return None


def _linked(db: Session, user: User, identity: SocialIdentity) -> bool:
    return (
        db.scalar(
            select(SocialAccount.id).where(
                SocialAccount.user_id == user.id,
                SocialAccount.provider == identity.provider,
                SocialAccount.provider_user_id == identity.provider_user_id,
            )
        )
        is not None
    )


def _fail(
    db: Session, user: User, *, action: str, via: str, ip: str, detail: dict
) -> HTTPException:
    # 실패 횟수는 확인 전에 [claim_attempt] 가 이미 셌다(#3238).
    audit.record(
        db,
        event=audit.REAUTH_FAILED,
        user_id=user.id,
        ip=ip,
        success=False,
        detail=f"action={action} via={via}",
    )
    return HTTPException(status_code=400, detail=detail)


def require(
    db: Session,
    user: User,
    *,
    action: str,
    ip: str,
    current_password: str | None,
    social_provider: str | None,
    social_token: str | None,
) -> str:
    """본인 확인을 통과하면 확인 수단(`password`|`social`)을, 아니면 HTTPException.

    값을 아예 보내지 않은 것(`reauth_required`)은 실패로 세지 않는다 — 옛 빌드가
    본문 없이 부른 것일 뿐 추측 시도가 아니다. 실패 기록은 [audit.record] 로 바로
    커밋하므로, 호출부는 다른 변경을 세션에 얹기 **전에** 부른다.

    값을 보낸 시도는 확인 **전에** 센다(`claim_attempt`, #3238). 확인이 맞으면 지운다
    — 틀린 뒤에 세면 확인을 기다리는 동시 요청이 모두 잠금 판정을 통과한다.
    """
    settings = get_settings()
    key = fail_key(user.id)
    limit = settings.password_change_max_failures
    window = float(settings.login_lockout_seconds)
    ensure_unlocked(key, limit, window)
    if user.hashed_password:
        if not (current_password or ""):
            raise HTTPException(status_code=400, detail=REAUTH_REQUIRED)
        claim_attempt(key, limit, window)
        if not verify_password(current_password or "", user.hashed_password):
            raise _fail(
                db, user, action=action, via="password", ip=ip,
                detail=INVALID_CURRENT_PASSWORD,
            )
        clear_failures(key)
        return "password"

    provider = (social_provider or "").strip().lower()
    token = (social_token or "").strip()
    if not (provider and token):
        raise HTTPException(status_code=400, detail=REAUTH_REQUIRED_SOCIAL)
    claim_attempt(key, limit, window)
    identity = _verify_social(provider, token)
    if identity is None or not _linked(db, user, identity):
        raise _fail(db, user, action=action, via="social", ip=ip, detail=INVALID_REAUTH)
    clear_failures(key)
    return "social"
