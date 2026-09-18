"""
사용자 라우터 — 프론트 계약 정렬.

  GET  /users/me           -> { id, name, email }
  GET  /users/me/health    -> { profile, risk, activity_points, activity_rank, settings[] }
  POST /auth/login         -> { access_token, token_type }   (Stage 4 대비)
  POST /auth/register      -> { id, name, email }             (Stage 4 대비)

데이터 엔드포인트(/users/me*)는 토큰 없으면 데모 사용자로 동작.
"""

from __future__ import annotations

import uuid
from typing import Annotated

import jwt
from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser, RequireMember
from app.core.rate_limit import rate_limit
from app.services.audit import client_ip, record as audit
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_refresh_claims,
    hash_password,
    verify_password,
)
from app.db.session import get_db
from app.models.models import AccountDeletionReason, HealthProfile, User
from app.schemas.user import (
    AccountDeleteRequest,
    HealthGoalsUpdate,
    HealthProfileBrief,
    OnboardingRequest,
    PairingCodeOut,
    ProfileUpdate,
    ProfileView,
    RefreshRequest,
    RiskInfo,
    SettingItem,
    Token,
    TrainerRegister,
    UserHealth,
    UserMe,
    UserRegister,
)
from app.services import (
    health_goal_change,
    member_pairing_service,
    reservation_service,
    token_revocation,
    trainer_signup_service,
)
from app.services.health_service import DEMO_SETTINGS
from app.services.profile_format import name_from_email

router = APIRouter(tags=["users"])


@router.get("/users/me", response_model=UserMe)
def get_me(current_user: CurrentUser) -> UserMe:
    return UserMe(id=current_user.id, name=current_user.name, email=current_user.email)


@router.get("/users/me/health", response_model=UserHealth)
def get_my_health(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> UserHealth:
    profile = current_user.health_profile

    # risk: 저장된 프로필 있으면 사용, 없으면 데모 기본값(프론트 mock 과 동일)
    if profile and profile.risk_title:
        risk = RiskInfo(
            title=profile.risk_title, body=profile.risk_body, level=profile.risk_level
        )
        rank = profile.activity_rank
    else:
        risk = RiskInfo(
            title="고혈압·당뇨 위험 주의",
            body="최근 혈압과 혈당 추세가 다소 높습니다. 식단·운동 관리에 신경 써주세요.",
            level="medium",
        )
        rank = 14

    # 포인트는 위험도와 따로 읽는다(#1786). 예전에는 위험 문구가 없는 프로필에
    # 데모 숫자 1240 을 돌려줘, 기록으로 적립해도 화면의 잔액이 움직이지 않았다.
    # 데모 회원의 시작 잔액 1240 은 시드가 프로필에 넣는다.
    points = profile.activity_points if profile is not None else 0

    return UserHealth(
        profile=HealthProfileBrief(
            id=current_user.id, name=current_user.name, email=current_user.email
        ),
        risk=risk,
        activity_points=points,
        activity_rank=rank,
        settings=[SettingItem(**s) for s in DEMO_SETTINGS],
    )


# ---- 프로필 / 온보딩 / 탈퇴 ----


def _get_or_create_profile(db: Session, user: User) -> HealthProfile:
    """사용자의 HealthProfile 을 가져오거나(없으면) 생성한다."""
    profile = user.health_profile
    if profile is None:
        profile = HealthProfile(user_id=user.id)
        db.add(profile)
        db.flush()
    return profile


def _profile_view(user: User) -> ProfileView:
    p = user.health_profile
    return ProfileView(
        id=user.id,
        name=user.name,
        email=user.email,
        phone=p.phone if p else "",
        birth_date=p.birth_date if p else "",
        gender=p.gender if p else "",
        height_cm=p.height_cm if p else None,
        weight_kg=p.weight_kg if p else None,
        conditions=p.conditions if p else "",
        goals=p.goals if p else "",
        daily_calories=p.daily_calories if p else None,
        daily_sodium_mg=p.daily_sodium_mg if p else None,
        daily_sugar_g=p.daily_sugar_g if p else None,
        daily_carbs_g=p.daily_carbs_g if p else None,
        daily_protein_g=p.daily_protein_g if p else None,
        daily_fat_g=p.daily_fat_g if p else None,
        weekly_workout_goal=p.weekly_workout_goal if p else None,
        weekly_exercise_minutes_goal=(p.weekly_exercise_minutes_goal if p else None),
        weekly_burn_goal=p.weekly_burn_goal if p else None,
        daily_burn_kcal=p.daily_burn_kcal if p else None,
        weekly_cardio_minutes=p.weekly_cardio_minutes if p else None,
        weekly_strength_sets=p.weekly_strength_sets if p else None,
        weekly_flexibility_minutes=(p.weekly_flexibility_minutes if p else None),
        onboarded=p.onboarded if p else False,
        focus_changed_by=p.focus_changed_by if p else None,
        focus_changed_at=p.focus_changed_at if p else None,
    )


@router.get("/users/me/profile", response_model=ProfileView)
def get_my_profile(current_user: CurrentUser) -> ProfileView:
    """내 프로필 통합 뷰(인구통계·목표·온보딩 여부). 조회는 데모 폴백 허용."""
    return _profile_view(current_user)


@router.post("/users/me/onboarding", response_model=ProfileView)
def submit_onboarding(
    payload: OnboardingRequest,
    user: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> ProfileView:
    """최초 온보딩 저장. 제공된 필드만 반영하고 onboarded=True 로 표시."""
    data = payload.model_dump(exclude_unset=True)
    if "name" in data and data["name"] is not None:
        user.name = data.pop("name")
    else:
        data.pop("name", None)

    profile = _get_or_create_profile(db, user)
    before = profile.conditions
    for field, value in data.items():
        setattr(profile, field, value)
    profile.onboarded = True
    # 처음 고른 목표도 회원이 정한 목표다 — 담당 트레이너가 이미 있으면 알린다(#1832).
    health_goal_change.record_member_change(db, profile, before=before, member=user)

    db.commit()
    db.refresh(user)
    return _profile_view(user)


@router.put("/users/me/health-goals", response_model=ProfileView)
def update_health_goals(
    payload: HealthGoalsUpdate,
    user: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> ProfileView:
    """건강 목표(식단 일일 6종 + 운동 7종) 저장. 제공된 필드만 반영.

    운동 목표는 운동 탭이 견주는 축과 같다 (#1139) — 소모 칼로리는 하루,
    유산소·근력·스트레칭은 한 주다.
    """
    profile = _get_or_create_profile(db, user)
    before = profile.conditions
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(profile, field, value)
    # 목표 칩이 바뀐 저장이면 기록하고 담당 트레이너에게 알린다(#1832).
    health_goal_change.record_member_change(db, profile, before=before, member=user)
    db.commit()
    db.refresh(user)
    return _profile_view(user)


@router.put("/users/me", response_model=ProfileView)
def update_me(
    payload: ProfileUpdate,
    user: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> ProfileView:
    """내 프로필 모달 저장: 이름/이메일(중복검사)/전화/생년월일."""
    data = payload.model_dump(exclude_unset=True)

    new_email = data.get("email")
    if new_email is not None and new_email != user.email:
        dup = db.scalar(select(User).where(User.email == new_email, User.id != user.id))
        if dup is not None:
            raise HTTPException(status_code=409, detail="이미 사용 중인 이메일입니다.")
        user.email = new_email
    if data.get("name") is not None:
        user.name = data["name"]

    profile = _get_or_create_profile(db, user)

    # 있던 연락처는 지울 수 없다(#1883). 회원 가입 화면은 전화번호를 **필수**로
    # 받는데(#1634) 이 화면에서 비울 수 있으면 그 필수가 무의미해지고, 트레이너가
    # 담당 회원에게 연락할 방법이 사라진다.
    #
    # 반대로 처음부터 없던 회원(소셜 로그인 가입자와 #1634 이전 가입자는
    # 연락처를 넣을 자리가 없었다)에게는 요구하지 않는다 — 이름만 고치려는
    # 사람에게 전화번호를 내놓으라고 막는 화면이 된다.
    if data.get("phone") == "" and profile.phone:
        raise HTTPException(status_code=422, detail="전화번호는 비울 수 없습니다.")

    for field in (
        "phone",
        "birth_date",
        "gender",
        "height_cm",
        "weight_kg",
        "goals",
    ):
        if field in data:
            setattr(profile, field, data[field])

    db.commit()
    db.refresh(user)
    return _profile_view(user)


# ---- 트레이너와 데이터 동기화 (#1634) ----


def _pairing_out(row) -> PairingCodeOut:
    from app.core import clock

    remaining = int((row.expires_at - clock.now()).total_seconds())
    return PairingCodeOut(
        code=row.code,
        expires_at=row.expires_at,
        expires_in_seconds=max(remaining, 0),
    )


@router.post(
    "/users/me/pairing-code",
    response_model=PairingCodeOut,
    dependencies=[Depends(rate_limit("pairing-code"))],
)
def issue_pairing_code(
    user: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> PairingCodeOut:
    """트레이너에게 불러 줄 6자리 동기화 코드를 발급한다.

    **이 호출이 데이터 공유 동의다** (#1022). 코드를 쓴 트레이너는 그 자리에서
    담당이 되고 회원의 식단·운동·건강 기록을 읽는다. 화면이 그 범위를 말한 뒤
    회원이 누르는 버튼이 여기로 온다.

    유효한 코드가 남아 있으면 그대로 돌려준다 — 화면을 다시 열 때마다 새로
    뽑으면 트레이너가 이미 받아 적은 값이 말없이 무효가 된다.
    """
    return _pairing_out(member_pairing_service.issue(db, user.id))


@router.delete("/users/me/pairing-code", status_code=204)
def revoke_pairing_code(
    user: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> None:
    """띄워 둔 코드를 버린다. 화면을 닫으면 호출한다.

    만료를 기다리지 않는 것은 회원이 그만두겠다고 표시한 것이기 때문이다 —
    발급이 동의였으니 취소도 즉시 반영돼야 한다.
    """
    member_pairing_service.revoke(db, user.id)


#: 탈퇴 화면이 보여 주는 사유. 앱과 같은 목록이고, 모르는 값은 버린다 —
#: 자유 입력을 받지 않는 이유는 그 칸에 무엇이 적힐지 알 수 없기 때문이다(#2019).
DELETION_REASONS: frozenset[str] = frozenset(
    {
        "privacy",
        "rarely_used",
        "hard_to_use",
        "too_many_notifications",
        "found_alternative",
        "other",
    }
)


@router.delete("/users/me")
def delete_me(
    user: RequireMember,
    db: Annotated[Session, Depends(get_db)],
    payload: AccountDeleteRequest | None = None,
) -> dict:
    """회원 탈퇴. 예약 좌석을 복구한 뒤 프로필·식단·운동·일정·알림·
    소셜계정·개인 코치문서를 함께 삭제한다.

    고른 사유가 있으면 **회원 행과 잇지 않고** 따로 남긴다(#2019). 회원은 이
    요청으로 사라지므로 FK 를 걸면 남길 수가 없고, 남기는 것도 사유 코드와
    시각뿐이다.

    사유는 없어도 된다. 탈퇴를 막는 조건이 아니라 물어보는 자리일 뿐이다.
    """
    for reason in sorted(set(payload.reasons if payload else []) & DELETION_REASONS):
        db.add(
            AccountDeletionReason(
                id=f"del-{uuid.uuid4().hex[:12]}",
                reason=reason,
            )
        )
    reservation_service.cancel_member_reservations_for_account_deletion(db, user.id)
    db.delete(user)
    db.commit()
    return {"status": "deleted"}


# ---- 인증 (Stage 4 대비, 지금도 동작) ----


@router.post(
    "/auth/register",
    response_model=UserMe,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(rate_limit("auth-register"))],
)
def register(
    request: Request,
    payload: UserRegister,
    db: Annotated[Session, Depends(get_db)],
) -> UserMe:
    exists = db.scalar(select(User).where(User.email == payload.email))
    if exists:
        audit(
            db,
            event="auth.register",
            ip=client_ip(request),
            success=False,
            detail=payload.email,
        )
        raise HTTPException(status_code=409, detail="이미 가입된 이메일입니다.")
    user = User(
        id=f"user-{uuid.uuid4().hex[:12]}",
        email=payload.email,
        # 이름을 보내지 않으면 이메일 로컬 파트로 채운다. 컬럼 길이(100)에
        # 맞춰 자르는 것이 `name_from_email` 의 몫이다 — 이메일은 255자까지
        # 받으므로(#1780), 자르지 않으면 이름을 안 보냈을 뿐인데 가입이 500 으로
        # 떨어졌다(#1887).
        name=payload.name or name_from_email(payload.email),
        hashed_password=hash_password(payload.password),
    )
    db.add(user)
    # 가입 화면에서 받은 전화번호를 프로필에 옮긴다 (#1634). 예전에는 MY 탭
    # 프로필 편집에서만 넣을 수 있어, 가입 직후에는 트레이너가 연락할 방법도
    # 회원을 알아볼 방법도 없었다.
    if payload.phone:
        db.add(HealthProfile(user_id=user.id, phone=payload.phone))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409, detail="이미 가입된 이메일입니다."
        ) from None
    db.refresh(user)
    audit(
        db, event="auth.register", user_id=user.id, ip=client_ip(request), success=True
    )
    return UserMe(id=user.id, name=user.name, email=user.email)


@router.post(
    "/auth/trainer/register",
    response_model=UserMe,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(rate_limit("auth-register"))],
)
def register_trainer(
    request: Request,
    payload: TrainerRegister,
    db: Annotated[Session, Depends(get_db)],
) -> UserMe:
    """헬스장 초대 코드로 트레이너 계정을 만든다. (#475)

    `/auth/register` 와 나누는 이유: 그쪽은 `role='member'` 를 만든다. 한 엔드포인트에
    역할 분기를 넣으면 코드 없이 트레이너를 만들 수 있는 경로가 생기기 쉽다.

    코드가 소속 헬스장을 결정한다 — 소속 없는 트레이너는 상담 대상이 될 수 없어
    (#443·#451) 가입 직후 아무것도 못 하는 상태가 된다.

    회원 가입과 같은 rate limit 버킷을 쓴다. 코드를 무작위로 넣어 보는 시도도
    가입 시도이므로 같은 한도가 맞다.
    """
    try:
        trainer = trainer_signup_service.register_trainer(db, payload)
    except trainer_signup_service.InviteCodeInvalid as exc:
        audit(
            db,
            event="auth.trainer_register",
            ip=client_ip(request),
            success=False,
            detail=payload.email,
        )
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except trainer_signup_service.TrainerEmailTaken as exc:
        audit(
            db,
            event="auth.trainer_register",
            ip=client_ip(request),
            success=False,
            detail=payload.email,
        )
        raise HTTPException(status_code=409, detail=str(exc)) from exc

    audit(
        db,
        event="auth.trainer_register",
        user_id=trainer.id,
        ip=client_ip(request),
        success=True,
    )
    return UserMe(id=trainer.id, name=trainer.name, email=trainer.email)


@router.post(
    "/auth/login",
    response_model=Token,
    dependencies=[Depends(rate_limit("auth-login"))],
)
def login(
    request: Request,
    form: Annotated[OAuth2PasswordRequestForm, Depends()],
    db: Annotated[Session, Depends(get_db)],
) -> Token:
    user = db.scalar(select(User).where(User.email == form.username))
    if (
        not user
        or not user.is_active
        or not verify_password(form.password, user.hashed_password)
    ):
        audit(
            db,
            event="auth.login",
            ip=client_ip(request),
            success=False,
            detail=form.username,
        )
        raise HTTPException(
            status_code=401, detail="이메일 또는 비밀번호가 올바르지 않습니다."
        )
    audit(db, event="auth.login", user_id=user.id, ip=client_ip(request), success=True)
    return Token(
        access_token=create_access_token(user.id),
        refresh_token=create_refresh_token(user.id),
    )


@router.post(
    "/auth/refresh",
    response_model=Token,
    dependencies=[Depends(rate_limit("auth-refresh"))],
)
def refresh(
    payload: RefreshRequest,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
) -> Token:
    """refresh 토큰으로 새 access(+refresh) 토큰 발급(회전).

    회전에 쓰인 토큰은 **그 자리에서 폐기된다** — refresh 토큰은 일회용이다.
    이미 쓴 토큰이 다시 오면 정상 사용자와 탈취자 둘 중 하나가 같은 토큰을 들고
    있다는 뜻이라, 회전해 주지 않고 거부하고 감사 로그에 남긴다(#966).
    """
    invalid = HTTPException(status_code=401, detail="유효하지 않은 refresh 토큰입니다.")
    try:
        claims = decode_refresh_claims(payload.refresh_token)
    except jwt.InvalidTokenError:
        raise invalid
    user = db.scalar(select(User).where(User.id == claims.subject))
    if user is None or not user.is_active:
        raise invalid
    first_use = token_revocation.revoke(
        db, jti=claims.jti, user_id=user.id, expires_at=claims.expires_at
    )
    if not first_use:
        # 로그아웃된 토큰이거나 이미 회전에 쓰인 토큰이다. 어느 쪽이든 여기서 끝난다.
        audit(
            db,
            event="auth.refresh_reuse",
            user_id=user.id,
            ip=client_ip(request),
            success=False,
        )
        raise invalid
    return Token(
        access_token=create_access_token(user.id),
        refresh_token=create_refresh_token(user.id),
    )


@router.post(
    "/auth/logout",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(rate_limit("auth-logout"))],
)
def logout(
    payload: RefreshRequest,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
) -> None:
    """받은 refresh 토큰을 폐기한다 — 서버 쪽에서 세션을 끊는다.

    access 토큰을 요구하지 않는다. 로그아웃은 접근 토큰이 이미 만료된 상태에서도
    되어야 하고, 여기서 하는 일은 **제시한 토큰 하나를 죽이는 것**뿐이라 그 토큰을
    가진 것 자체가 자격이다.

    못 알아본 토큰에도 204 로 답한다. 클라이언트가 할 일(로컬 저장소 비우기)은
    어느 쪽이든 같고, 상태 코드로 "이 토큰은 살아 있다"를 알려 줄 이유도 없다.
    """
    try:
        claims = decode_refresh_claims(payload.refresh_token)
    except jwt.InvalidTokenError:
        audit(
            db,
            event="auth.logout",
            ip=client_ip(request),
            success=False,
            detail="유효하지 않은 refresh 토큰",
        )
        return None
    token_revocation.revoke(
        db, jti=claims.jti, user_id=claims.subject, expires_at=claims.expires_at
    )
    audit(
        db,
        event="auth.logout",
        user_id=claims.subject,
        ip=client_ip(request),
        success=True,
    )
    return None
