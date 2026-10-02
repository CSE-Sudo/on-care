"""소셜 로그인 라우터.

  POST /auth/social/{provider}  { token }  ->  { access_token, refresh_token }

provider(kakao/google/naver/apple)에서 토큰을 검증해 사용자를 찾거나 만들고,
우리 서비스의 JWT(access+refresh)를 발급한다.
"""
from __future__ import annotations

import logging
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.core.rate_limit import rate_limit
from app.db.session import get_db
from app.services import auth_tokens
from app.services.audit import client_ip, record as audit
from app.services.contact_format import normalize_email
from app.models.models import SocialAccount, User
from app.schemas.user import LoginToken, SocialLoginRequest
from app.services.social.base import (
    SocialAuthError,
    SocialIdentity,
    SocialProviderResponseError,
)
from app.services.social.factory import get_verifier

logger = logging.getLogger(__name__)

router = APIRouter(tags=["auth"])

_AUTH_FAILED = "소셜 인증에 실패했습니다."
_PROVIDER_BAD_RESPONSE = "소셜 로그인 제공자의 응답을 확인하지 못했습니다. 잠시 후 다시 시도해 주세요."


def _find_or_create_user(db: Session, identity: SocialIdentity) -> User:
    # 1) 이미 연결된 소셜 계정이면 그 사용자
    account = db.scalar(
        select(SocialAccount).where(
            SocialAccount.provider == identity.provider,
            SocialAccount.provider_user_id == identity.provider_user_id,
        )
    )
    if account is not None:
        return db.scalar(select(User).where(User.id == account.user_id))

    # 2) 같은 이메일의 기존 사용자에 연결, 없으면 새 사용자 생성
    # 이메일은 가입과 같은 규칙(소문자)으로 맞춰 찾고 저장한다(#2816).
    email = normalize_email(identity.email or "")
    user: User | None = None
    if email:
        user = db.scalar(select(User).where(func.lower(User.email) == email))
    if user is None:
        user = User(
            id=f"user-{uuid.uuid4().hex[:12]}",
            email=email
            or normalize_email(
                f"{identity.provider}_{identity.provider_user_id}@social.oncare"
            ),
            name=identity.name or identity.provider,
            hashed_password="",  # 소셜 계정은 비밀번호 없음
        )
        db.add(user)
        db.flush()

    db.add(SocialAccount(
        user_id=user.id,
        provider=identity.provider,
        provider_user_id=identity.provider_user_id,
    ))
    db.commit()
    db.refresh(user)
    return user


def _complete_login(
    db: Session, identity: SocialIdentity, ip: str | None, provider: str
) -> LoginToken:
    """검증된 신원으로 사용자를 찾거나 만들고 감사 기록 뒤 토큰을 낸다. 동기(#2835)."""
    user = _find_or_create_user(db, identity)
    audit(db, event="auth.social", user_id=user.id, ip=ip, success=True, detail=provider)
    # 소셜로 처음 들어온 계정은 가입 화면을 거치지 않아 동의 기록이 없다(#2819) —
    # `consent_required` 가 참이 되어 앱이 가입 화면과 같은 동의 화면을 띄운다.
    return auth_tokens.issue_login_tokens(db, user)


@router.post(
    "/auth/social/{provider}",
    response_model=LoginToken,
    dependencies=[Depends(rate_limit("auth-social"))],
)
async def social_login(
    provider: str,
    payload: SocialLoginRequest,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
) -> LoginToken:
    """소셜 토큰 검증 → 사용자 조회·생성 → 토큰 발급.

    외부 검증만 `await` 하고, 동기 DB 작업(사용자 조회·생성·감사 기록)은 스레드풀로
    넘긴다(#2835). 이벤트 루프에서 돌면 그동안 다른 요청이 모두 멈춘다.
    """
    ip = client_ip(request)
    try:
        verifier = get_verifier(provider)
    except ValueError:
        raise HTTPException(status_code=400, detail="지원하지 않는 소셜 로그인입니다.")

    try:
        identity = await verifier.verify(payload.token)
    except NotImplementedError:
        raise HTTPException(status_code=status.HTTP_501_NOT_IMPLEMENTED, detail="아직 지원하지 않는 소셜 로그인입니다.")
    except SocialProviderResponseError as exc:
        # provider 가 200 에 HTML·깨진 JSON 등을 줬다. 토큰 문제가 아니므로 502.
        # 로그에는 예외 종류와 요약 메시지만 남긴다(토큰·응답 본문은 담지 않는다).
        logger.warning("소셜 로그인 provider 응답 형식 이상 provider=%s: %s", provider, exc)
        await run_in_threadpool(
            audit, db, event="auth.social", ip=ip, success=False, detail=provider
        )
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=_PROVIDER_BAD_RESPONSE)
    except SocialAuthError:
        await run_in_threadpool(
            audit, db, event="auth.social", ip=ip, success=False, detail=provider
        )
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=_AUTH_FAILED)
    except Exception as exc:  # noqa: BLE001 — adapter 가 놓친 예외도 감사 없이 500 이 되면 안 된다
        # 예외 메시지에는 요청 URL(google 은 쿼리에 토큰)이 섞일 수 있어 종류만 남긴다.
        logger.error(
            "소셜 로그인 검증 중 예상 못 한 예외 provider=%s type=%s",
            provider, type(exc).__name__,
        )
        await run_in_threadpool(
            audit, db, event="auth.social", ip=ip, success=False, detail=provider
        )
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=_PROVIDER_BAD_RESPONSE)

    return await run_in_threadpool(_complete_login, db, identity, ip, provider)
