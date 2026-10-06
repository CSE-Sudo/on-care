"""소셜 로그인 라우터.

  POST /auth/social/{provider}  { token }  ->  { access_token, refresh_token }
  POST /auth/social/kakao/code  { code, redirect_uri }  ->  { access_token }  (웹, #330)

provider(kakao/google)에서 토큰을 검증해 사용자를 찾거나 만들고,
우리 서비스의 JWT(access+refresh)를 발급한다. 카카오 웹 로그인은 SDK 가 토큰을 주지
않아, 먼저 인가 코드를 서버에서 카카오 access_token 으로 바꾼 뒤 같은 로그인 길을 탄다.
"""
from __future__ import annotations

import logging
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.core.rate_limit import rate_limit
from app.db.session import get_db
from app.services import auth_tokens
from app.services.audit import client_ip, record as audit
from app.services.contact_format import normalize_email
from app.models.models import SocialAccount, User
from app.schemas.user import (
    KakaoCodeExchangeRequest,
    KakaoCodeExchangeResponse,
    LoginToken,
    SocialLoginRequest,
)
from app.services.social import kakao as kakao_social
from app.services.social.base import (
    SocialAuthError,
    SocialIdentity,
    SocialProviderResponseError,
)
from app.services.social.factory import get_verifier

logger = logging.getLogger(__name__)

router = APIRouter(tags=["auth"])

_AUTH_FAILED = "소셜 계정을 인증하지 못했어요."
_PROVIDER_BAD_RESPONSE = "소셜 로그인 제공자의 응답을 확인하지 못했어요. 잠시 후 다시 시도해 주세요."
#: 확인되지 않은 이메일이 기존 계정의 이메일과 같을 때(#1551). 화면은 `code` 로 가른다.
#: 기존 계정이 비밀번호로 가입했는지 다른 소셜로 가입했는지는 밝히지 않는다.
_EMAIL_IN_USE = {
    "code": "social_email_in_use",
    "message": "이 이메일로 가입한 계정이 있어요. 처음 가입한 방법으로 로그인해 주세요.",
}


class SocialEmailInUse(Exception):
    """provider 가 확인하지 않은 이메일이 기존 계정의 이메일과 같다(#1551)."""


def _placeholder_email(identity: SocialIdentity) -> str:
    """확인된 이메일이 없을 때 쓰는 대체 이메일. provider 신원마다 하나라 겹치지 않는다."""
    return normalize_email(f"{identity.provider}_{identity.provider_user_id}@social.oncare")


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
    #
    # provider 가 소유를 확인한 이메일일 때만 그 이메일을 쓴다(#1551). 확인되지 않은
    # 이메일로 기존 계정을 찾으면, 남의 주소를 provider 계정에 적어 넣는 것만으로 그
    # 사람 계정에 로그인된다.
    #
    # - 확인 안 된 이메일이 **기존 계정의 이메일과 같으면** 연결도, 새 계정도 만들지
    #   않고 [SocialEmailInUse] 로 끝낸다. 조용히 따로 계정을 만들면 주인은 기록이 빈
    #   두 번째 계정에 들어가 영문을 모른다. 앱은 "처음 가입한 방법으로 로그인" 을 안내한다.
    # - 같은 계정이 없으면 새 계정을 만들되 그 주소를 계정 이메일로 쓰지 않는다 — 계정
    #   이메일은 재설정 메일·가입 중복 확인이 믿는 값이라, 확인 안 된 주소를 넣으면
    #   주인이 그 주소로 가입하지 못하고(409) 주소를 선점당한다. provider 신원으로
    #   만든 대체 이메일을 쓴다(이메일이 없을 때와 같다).
    claimed = normalize_email(identity.email or "")
    if claimed and not identity.email_verified:
        if db.scalar(select(User.id).where(func.lower(User.email) == claimed)):
            raise SocialEmailInUse()
    email = claimed if identity.email_verified else ""
    user: User | None = None
    if email:
        user = db.scalar(select(User).where(func.lower(User.email) == email))
    if user is not None and not user.is_active:
        # 쉬는 계정에는 연결하지 않고 돌려준다 — 거절은 호출부가 한다(#3252). 연결부터
        # 남기면 정지가 풀린 뒤 주인이 연결한 적 없는 소셜 계정으로 바로 로그인된다.
        return user
    if user is None:
        user = User(
            id=f"user-{uuid.uuid4().hex[:12]}",
            email=email or _placeholder_email(identity),
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
    """검증된 신원으로 사용자를 찾거나 만들고 감사 기록 뒤 토큰을 낸다. 동기(#2835).

    같은 신원의 첫 로그인이 동시에 오면 둘 다 "연결 없음" 을 보고 연결(또는 사용자)을
    만들다 유일 제약(`uq_social_provider_uid`·`users.email`)에서 만난다(#3238). 늦은
    쪽은 되돌리고 한 번 더 찾는다 — 먼저 끝난 쪽이 만든 연결로 같은 계정에 들어간다.

    쉬는(정지된) 계정에는 토큰을 주지 않는다(#3238). 비밀번호 로그인·refresh 와 같은
    401 이다 — 예전에는 200 과 토큰을 받고 다음 요청부터 401 이었다.
    """
    try:
        user = _find_or_create_user(db, identity)
    except IntegrityError:
        db.rollback()
        user = _find_or_create_user(db, identity)
    if user is None or not user.is_active:
        audit(
            db, event="auth.social", user_id=user.id if user else None, ip=ip,
            success=False, detail=f"{provider} reason=inactive",
        )
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=_AUTH_FAILED)
    audit(db, event="auth.social", user_id=user.id, ip=ip, success=True, detail=provider)
    # 소셜로 처음 들어온 계정은 가입 화면을 거치지 않아 동의 기록이 없다(#2819) —
    # `consent_required` 가 참이 되어 앱이 가입 화면과 같은 동의 화면을 띄운다.
    return auth_tokens.issue_login_tokens(db, user)


@router.post(
    "/auth/social/kakao/code",
    response_model=KakaoCodeExchangeResponse,
    dependencies=[Depends(rate_limit("auth-social"))],
)
async def kakao_code_exchange(
    payload: KakaoCodeExchangeRequest,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
) -> KakaoCodeExchangeResponse:
    """카카오 웹 로그인 인가 코드 → 카카오 access_token (#330).

    로그인·계정 생성은 하지 않는다. 앱이 받은 토큰을 `POST /auth/social/kakao`(로그인)나
    본인 확인(`social_token`)에 그대로 넣게 해, 웹과 모바일이 같은 검증을 탄다. 실패 응답은
    소셜 로그인과 같은 401·502 다.
    """
    ip = client_ip(request)
    try:
        token = await kakao_social.exchange_code(payload.code, payload.redirect_uri)
    except SocialProviderResponseError as exc:
        logger.warning("카카오 코드 교환 응답 형식 이상: %s", exc)
        await run_in_threadpool(
            audit, db, event="auth.social", ip=ip, success=False, detail="kakao code"
        )
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=_PROVIDER_BAD_RESPONSE)
    except SocialAuthError:
        await run_in_threadpool(
            audit, db, event="auth.social", ip=ip, success=False, detail="kakao code"
        )
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=_AUTH_FAILED)
    except Exception as exc:  # noqa: BLE001 — 로그인과 같은 이유로 감사 없이 500 이 되면 안 된다
        logger.error("카카오 코드 교환 중 예상 못 한 예외 type=%s", type(exc).__name__)
        await run_in_threadpool(
            audit, db, event="auth.social", ip=ip, success=False, detail="kakao code"
        )
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=_PROVIDER_BAD_RESPONSE)
    return KakaoCodeExchangeResponse(access_token=token)


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
        raise HTTPException(status_code=400, detail="지원하지 않는 소셜 로그인이에요.")

    try:
        identity = await verifier.verify(payload.token)
    except NotImplementedError:
        raise HTTPException(status_code=status.HTTP_501_NOT_IMPLEMENTED, detail="아직 지원하지 않는 소셜 로그인이에요.")
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

    try:
        return await run_in_threadpool(_complete_login, db, identity, ip, provider)
    except SocialEmailInUse:
        # 인증은 됐지만 로그인시키지 않았다 — 실패로 남기고 이유를 붙인다(#1551).
        await run_in_threadpool(
            audit, db, event="auth.social", ip=ip, success=False,
            detail=f"{provider} reason=email_in_use",
        )
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=_EMAIL_IN_USE)
