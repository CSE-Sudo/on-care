"""
인증 의존성.

프론트는 로그인(Stage 4) 전이라 토큰 없이도 데이터 화면이 떠야 합니다.
그래서 current_user 는 다음 규칙으로 동작합니다:

  1) Authorization: Bearer <유효한 토큰> 이 있으면 → 그 사용자
  2) 토큰이 아예 없으면 → 데모 사용자(user-7d4e9a2c5f18) 로 폴백(켜진 환경에서만)
  3) 토큰이 있는데 무효·만료·지난 세대이거나 사용자가 없으면 → 폴백과 무관하게 401 (#3160)

이렇게 하면 프론트가 USE_MOCK_API=false 로 전환해도(아직 토큰 없음)
화면이 데모 데이터로 정상 렌더되고, Stage 4 에서 로그인이 붙으면
자동으로 실제 사용자 데이터로 전환됩니다.

운영 배포 시 엄격 모드가 필요하면 require_auth 의존성을 쓰면 됩니다.
"""
from __future__ import annotations

from typing import Annotated, Optional

import jwt
from fastapi import Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.security import decode_access_claims
from app.db.init_db import DEMO_USER_ID
from app.db.session import get_db
from app.models.models import User
from app.services import auth_tokens, signup_consent


def _extract_bearer(request: Request) -> Optional[str]:
    auth = request.headers.get("Authorization", "")
    if auth.lower().startswith("bearer "):
        return auth[7:].strip()
    return None


def get_current_user(
    request: Request,
    db: Annotated[Session, Depends(get_db)],
) -> User:
    """토큰이 유효하면 그 사용자.

    - 토큰이 **없으면**: 개발/스테이징(demo_fallback_enabled)은 데모 사용자, 운영(prod)은 401.
    - 토큰이 **있는데** 무효·만료·지난 세대이거나 사용자가 없으면: 폴백과 무관하게 401.
      스테이징에서 만료 토큰이 데모 회원으로 처리되면 테스터에게 남의(데모) 기록이 보이고
      그 상태로 기록하면 데모 계정에 쌓인다. 401 을 받아야 앱이 갱신 토큰을 돌리고, 그것도
      거부되면 운영과 같이 로그인 화면으로 간다(#3160).
    """
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="인증이 필요해요.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    token = _extract_bearer(request)
    if token:
        try:
            claims = decode_access_claims(token)
        except jwt.InvalidTokenError:
            raise unauthorized from None
        user = db.scalar(select(User).where(User.id == claims.subject))
        # 탈퇴 등으로 사라진 사용자, 비밀번호 변경 전에 발급된 토큰(#2766), 비활성 계정은
        # 무효한 토큰과 같다.
        if (
            user is None
            or not auth_tokens.is_current(user, claims.token_version)
            or not user.is_active
        ):
            raise unauthorized
        # 회원 전용 API. 트레이너 계정은 /trainer/* 를 쓴다(역할 분리).
        if user.role == "trainer":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="회원 전용 API예요.",
            )
        ensure_consented(request, user, db)
        return user

    if get_settings().demo_fallback_enabled:
        demo = db.scalar(select(User).where(User.id == DEMO_USER_ID))
        if demo is None:
            raise HTTPException(status_code=500, detail="데모 사용자가 시드되지 않았어요.")
        return demo

    raise unauthorized


def require_auth(
    request: Request,
    db: Annotated[Session, Depends(get_db)],
) -> User:
    """엄격 모드: 유효한 토큰이 반드시 있어야 함 (로그인 도입 후 보호용 엔드포인트에 사용)."""
    token = _extract_bearer(request)
    exc = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="인증이 필요해요.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if not token:
        raise exc
    try:
        claims = decode_access_claims(token)
    except jwt.InvalidTokenError:
        raise exc from None
    user = db.scalar(select(User).where(User.id == claims.subject))
    if user is None or not user.is_active:
        raise exc
    # 비밀번호를 바꾸면 그 전에 다른 기기에 발급된 접근 토큰은 여기서 401 이 된다
    # (#2766). 클라이언트는 401 을 받아 refresh 를 시도하고, refresh 도 같은 이유로
    # 거부되어 세션 만료 안내와 함께 로그인 화면으로 간다.
    if not auth_tokens.is_current(user, claims.token_version):
        raise exc
    return user


def require_admin(
    user: Annotated[User, Depends(require_auth)],
) -> User:
    """관리자 전용: 유효 토큰 + is_admin. 아니면 403(미인증은 require_auth 가 401)."""
    if not user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="관리자 권한이 필요해요.")
    return user


def require_trainer(
    request: Request,
    user: Annotated[User, Depends(require_auth)],
    db: Annotated[Session, Depends(get_db)],
) -> User:
    """트레이너 전용: 유효 토큰 + role == 'trainer'. 데모 폴백 없음(회원 데모 사용자가
    트레이너 엔드포인트에 새어 들어가지 않도록). 미인증은 require_auth 가 401,
    회원 계정이면 403.

    필수 동의(약관·개인정보·만 14세)가 남은 트레이너도 403 `consent_required` 다
    ([ensure_consented], #3155). 트레이너는 회원의 건강정보를 열람하는 쪽이라,
    동의 화면을 거치지 않은 경로로도 동의 없이 쓰지 못하게 서버가 확인한다."""
    if user.role != "trainer":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="트레이너 권한이 필요해요.")
    ensure_consented(request, user, db)
    return user


def require_member(
    request: Request,
    user: Annotated[User, Depends(require_auth)],
    db: Annotated[Session, Depends(get_db)],
) -> User:
    """회원 전용(쓰기/삭제 등): 유효 토큰 + role == 'member'. 트레이너 계정이면 403.
    데모 폴백 없음(require_auth 기반). 읽기 폴백이 필요한 엔드포인트는 CurrentUser
    (get_current_user)가 이미 트레이너를 403 처리한다.

    필수 동의가 남은 계정은 403 `consent_required` 다([ensure_consented])."""
    if user.role != "member":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="회원 전용 API예요.")
    ensure_consented(request, user, db)
    return user


# ---- 필수 동의 확인 (#3088) ----

#: 필수 동의가 남은 계정도 부를 수 있는 라우트. `(메서드, /v1 을 뺀 경로)`.
#:
#: 회원 의존성(`CurrentUser`·`RequireMember`)과 트레이너 의존성(`RequireTrainer`,
#: #3155)을 쓰는 라우트는 **기본으로 막힌다** —
#: 새 라우트가 빠지지 않게 하려는 것이다. 여기에는 동의를 처리하는 데 필요한 경로만
#: 둔다. `/auth/*`(로그인·refresh·로그아웃·비밀번호 재설정)와 `POST /users/me/consents`
#: 는 회원 의존성을 쓰지 않아 처음부터 이 확인 밖이다.
#:
#: 동의 관리 경로(마케팅 동의 철회 등, #3007)가 생기면 함께 연다.
CONSENT_EXEMPT_ROUTES: dict[tuple[str, str], str] = {
    ("GET", "/users/me"): "앱이 동의가 필요한지 읽는 곳이다. 회원 앱 세션 복원은 "
    "이 경로의 401·403 을 로그인 만료로 본다.",
    ("DELETE", "/users/me"): "탈퇴는 동의하지 않은 회원도 할 수 있어야 한다.",
    ("GET", "/trainer/me"): "트레이너 웹이 로그인·세션 복구 때 프로필을 읽는 곳이다. "
    "막으면 동의 화면에 닿기 전에 로그인이 실패한다.",
    ("DELETE", "/trainer/me"): "탈퇴는 동의하지 않은 트레이너도 할 수 있어야 한다.",
}


#: 서버가 필수 동의를 확인하는 역할. (#3155 에서 트레이너 추가)
_CONSENT_CHECKED_ROLES = frozenset({"member", "trainer"})


def _route_key(request: Request) -> tuple[str, str] | None:
    """요청이 잡힌 라우트의 `(메서드, /v1 을 뺀 경로 템플릿)`."""
    route = request.scope.get("route")
    path = getattr(route, "path", None)
    if not path:
        return None
    prefix = get_settings().api_v1_prefix
    if prefix and path.startswith(prefix):
        path = path[len(prefix):]
    return request.method.upper(), path


def ensure_consented(request: Request, user: User, db: Session) -> None:
    """회원·트레이너 계정의 역할별 필수 동의가 끝났는지 본다. (#3088, #3155)

    회원은 약관·개인정보·건강정보·만 14세, 트레이너는 약관·개인정보·만 14세다
    (`signup_consent.REQUIRED_BY_ROLE`). 그 밖의 역할은 보지 않는다.

    동의는 지금까지 앱 화면이 동의 화면을 먼저 띄우는 것으로만 지켜졌다. 앱을
    거치지 않거나 옛 빌드로 부르면 동의 없이 건강정보가 저장되고 외부 AI 로
    나갔다. 그래서 회원 데이터·AI API 앞에서 서버가 직접 확인한다.

    남은 항목이 있으면 403 `{"code": "consent_required", "missing": [...]}` —
    `POST /users/me/consents` 의 422 detail 과 같은 모양이다. 문서 버전이 올라
    옛 버전에만 동의한 계정, 동의를 철회한 계정도 여기 걸린다.

    한 요청 안에서는 한 번만 조회한다(회원 의존성이 겹쳐도).
    """
    if user.role not in _CONSENT_CHECKED_ROLES:
        return
    key = _route_key(request)
    if key is not None and key in CONSENT_EXEMPT_ROUTES:
        return
    cached = getattr(request.state, "consent_pending", None)
    if cached is not None and cached[0] == user.id:
        pending = cached[1]
    else:
        pending = signup_consent.pending_kinds(db, user)
        request.state.consent_pending = (user.id, pending)
    if pending:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "consent_required", "missing": pending},
        )


CurrentUser = Annotated[User, Depends(get_current_user)]
# 엄격 인증(쓰기/삭제 등 보호 엔드포인트용) — 데모 폴백 없음
RequireUser = Annotated[User, Depends(require_auth)]
# 회원 전용(트레이너 계정 접근 차단) — 데모 폴백 없음
RequireMember = Annotated[User, Depends(require_member)]
# 관리자 전용(공공문서 업로드 등)
RequireAdmin = Annotated[User, Depends(require_admin)]
# 트레이너 전용(트레이너 앱 엔드포인트)
RequireTrainer = Annotated[User, Depends(require_trainer)]
