"""탈퇴한 회원의 Apple 토큰 철회 (#3499).

Apple 은 Sign in with Apple 로 만든 계정을 앱에서 지울 때 Apple REST API 로 그 사용자의
토큰을 철회하라고 안내한다(계정 삭제 안내, App Review Guideline 5.1.1(v)). 철회하면
회원의 "Apple ID 를 사용하는 앱" 목록에서 On-Care 가 빠지고, 다시 애플로 로그인하면
처음 가입처럼 이름·이메일 공유를 다시 묻는다.

리프레시 토큰을 DB 에 따로 보관하지 않는다. 애플 계정의 탈퇴는 본인 확인으로 애플
로그인을 한 번 더 거치므로(`services/reauth.py`), 그때 앱이 받은 `authorization_code`
를 탈퇴 요청에 함께 보낸다. 서버는 계정을 지운 뒤 그 코드를 토큰으로 바꾸고
(`/auth/token`) 받은 토큰을 철회한다(`/auth/revoke`).

두 호출 모두 client secret 이 필요하다 — Sign in with Apple 키(.p8)로 서명한 ES256
JWT 다(`iss`=팀 ID, `sub`=client_id, `aud`=https://appleid.apple.com, 헤더 `kid`=키 ID).

**철회는 탈퇴를 막지 않는다.** 계정·기록은 이미 지워졌고, 철회가 실패해도 회원이
설정 앱에서 직접 연결을 끊을 수 있다. 키가 없거나 Apple 이 실패하면 로그만 남긴다.
코드·토큰·키 값은 로그에 남기지 않는다.
https://developer.apple.com/documentation/sign_in_with_apple/revoke_tokens
"""
from __future__ import annotations

import logging
import time

import httpx
import jwt

from app.core.config import Settings, get_settings

logger = logging.getLogger(__name__)

APPLE_AUDIENCE = "https://appleid.apple.com"
TOKEN_URL = "https://appleid.apple.com/auth/token"
REVOKE_URL = "https://appleid.apple.com/auth/revoke"

#: client secret 수명(초). Apple 은 최대 6개월을 허용하지만 호출할 때마다 새로 만들므로
#: 짧게 둔다.
_SECRET_LIFETIME_SEC = 300
_TIMEOUT_SEC = 5.0


def _private_key(settings: Settings) -> str:
    """PEM 본문. 비밀 저장소가 줄바꿈을 `\\n` 글자로 담아 주는 경우도 받는다."""
    return settings.apple_private_key.strip().replace("\\n", "\n")


def client_secret(settings: Settings, client_id: str, *, now: int | None = None) -> str:
    """Apple REST API 의 client secret(ES256 JWT)."""
    issued = int(time.time()) if now is None else now
    return jwt.encode(
        {
            "iss": settings.apple_team_id.strip(),
            "iat": issued,
            "exp": issued + _SECRET_LIFETIME_SEC,
            "aud": APPLE_AUDIENCE,
            "sub": client_id,
        },
        _private_key(settings),
        algorithm="ES256",
        headers={"kid": settings.apple_key_id.strip()},
    )


def revoke_with_code(
    authorization_code: str | None,
    *,
    settings: Settings | None = None,
    http: httpx.Client | None = None,
) -> bool:
    """코드를 토큰으로 바꿔 철회한다. 철회까지 끝나면 True, 건너뛰거나 실패하면 False.

    예외를 던지지 않는다 — 부르는 쪽(탈퇴)은 결과와 상관없이 끝난다.
    """
    current = settings or get_settings()
    code = (authorization_code or "").strip()
    if not code:
        logger.warning("apple 토큰 철회 건너뜀: 탈퇴 요청에 authorization_code 가 없음")
        return False
    if not current.apple_revoke_configured:
        logger.error(
            "apple 토큰 철회 건너뜀: APPLE_TEAM_ID·APPLE_KEY_ID·APPLE_PRIVATE_KEY·"
            "APPLE_CLIENT_IDS 중 비어 있는 값이 있음"
        )
        return False

    # iOS 앱의 코드는 번들 ID 앞으로 발급된다. 허용 목록의 첫 값이 그 번들 ID 다.
    client_id = current.apple_client_id_list[0]
    try:
        secret = client_secret(current, client_id)
    except Exception as exc:  # noqa: BLE001 — 키 형식 오류 등
        logger.error("apple 토큰 철회 실패: client secret 서명 불가(%s)", type(exc).__name__)
        return False

    owns_client = http is None
    client = http or httpx.Client(timeout=_TIMEOUT_SEC)
    try:
        resp = client.post(
            TOKEN_URL,
            data={
                "client_id": client_id,
                "client_secret": secret,
                "code": code,
                "grant_type": "authorization_code",
            },
        )
        if resp.status_code != 200:
            logger.warning("apple 토큰 철회 실패: 코드 교환 %s", resp.status_code)
            return False
        try:
            tokens = resp.json()
        except ValueError:
            logger.warning("apple 토큰 철회 실패: 코드 교환 응답이 JSON 이 아님")
            return False
        refresh = tokens.get("refresh_token") if isinstance(tokens, dict) else None
        access = tokens.get("access_token") if isinstance(tokens, dict) else None
        token, hint = (refresh, "refresh_token") if refresh else (access, "access_token")
        if not isinstance(token, str) or not token:
            logger.warning("apple 토큰 철회 실패: 코드 교환 응답에 토큰이 없음")
            return False
        resp = client.post(
            REVOKE_URL,
            data={
                "client_id": client_id,
                "client_secret": secret,
                "token": token,
                "token_type_hint": hint,
            },
        )
        if resp.status_code != 200:
            logger.warning("apple 토큰 철회 실패: revoke %s", resp.status_code)
            return False
    except httpx.HTTPError as exc:
        logger.warning("apple 토큰 철회 실패: 요청 오류(%s)", type(exc).__name__)
        return False
    finally:
        if owns_client:
            client.close()
    logger.info("apple 토큰 철회 완료")
    return True
