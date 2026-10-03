"""
사용자 라우터 — 프론트 계약 정렬.

  GET  /users/me           -> { id, name, email }
  GET  /users/me/health    -> { profile, activity_points }
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
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser, RequireMember, RequireUser
from app.core import clock
from app.core.config import get_settings
from app.core.locale import get_request_locale
from app.core.rate_limit import (
    check_key,
    clear_failures,
    ensure_unlocked,
    limiter,
    rate_limit,
    record_failure,
    register_email_key,
)
from app.services.audit import client_ip, record as audit
from app.services.audit_email import masked_email
from app.core.security import (
    decode_refresh_claims,
    hash_password,
    verify_password,
)
from app.db.session import get_db
from app.models.models import AccountDeletionReason, HealthProfile, User
from app.schemas.user import (
    AccountDeleteRequest,
    ConsentStatus,
    ConsentSubmit,
    MemberPasswordChange,
    PasswordChanged,
    PasswordResetConfirm,
    PasswordResetDone,
    PasswordResetRequest,
    PasswordResetRequested,
    HealthGoalsUpdate,
    HealthProfileBrief,
    LoginToken,
    OnboardingRequest,
    PairingCodeOut,
    ProfileUpdate,
    ProfileView,
    RefreshRequest,
    Token,
    TrainerRegister,
    UserHealth,
    UserMe,
    UserRegister,
)
from app.services import (
    attachment_cleanup,
    auth_tokens,
    consultation_service,
    data_consent_service,
    health_goal_change,
    member_departure,
    member_pairing_service,
    name_change,
    password_reset,
    reservation_service,
    signup_consent,
    token_revocation,
    trainer_signup_service,
    weekly_challenge_service,
)
from app.services.diet_coach_inputs import effective_protein_g
from app.services.contact_format import normalize_email
from app.services.profile_format import name_from_email

router = APIRouter(tags=["users"])


@router.get("/users/me", response_model=UserMe)
def get_me(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> UserMe:
    # 아직 동의하지 않은 필수 항목을 함께 준다(#2819). 앱은 이 값으로 다른
    # 화면보다 먼저 동의 화면을 띄운다.
    pending = signup_consent.pending_kinds(db, current_user)
    return UserMe(
        id=current_user.id,
        name=current_user.name,
        email=current_user.email,
        role=current_user.role,
        consent_required=bool(pending),
        consent_pending=pending,
    )


@router.post("/users/me/consents", response_model=ConsentStatus)
def submit_consents(
    payload: ConsentSubmit,
    user: RequireUser,
    db: Annotated[Session, Depends(get_db)],
) -> ConsentStatus:
    """가입 뒤 동의 화면에서 받은 항목을 남긴다. (#2819)

    동의 절차가 생기기 전에 가입한 계정, 소셜 로그인으로 처음 들어온 계정, 문서
    버전이 올라간 계정이 다음 로그인 때 거치는 화면이 부른다. 회원·트레이너 모두
    쓴다 — 필수 항목은 계정 역할로 고른다.

    필수 항목이 하나라도 빠지면 아무것도 남기지 않고 422 다. 일부만 남기면
    화면은 다시 뜨는데 어떤 항목은 이미 동의한 것으로 남아, 무엇에 언제 동의했는지
    이력이 흐려진다.
    """
    missing = signup_consent.missing_required(user.role, payload.consents)
    if missing:
        raise HTTPException(
            status_code=422,
            detail={"code": "consent_required", "missing": missing},
        )
    signup_consent.record(db, user.id, payload.consents)
    db.commit()
    pending = signup_consent.pending_kinds(db, user)
    return ConsentStatus(consent_required=bool(pending), consent_pending=pending)


@router.get("/users/me/health", response_model=UserHealth)
def get_my_health(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> UserHealth:
    # 끝난 주의 챌린지를 먼저 판정한다(#1789) — 보상이 들어온 잔액을 보여 준다.
    weekly_challenge_service.settle_quietly(db, current_user.id)
    profile = current_user.health_profile

    # 위험 문구·활동 순위·설정 메뉴는 싣지 않는다(#2903). 앱이 읽지 않는 자리에
    # 고정 문구·고정 순위 14·데모 설정 목록을 채워 보냈다.

    # 포인트는 위험도와 따로 읽는다(#1786). 예전에는 위험 문구가 없는 프로필에
    # 데모 숫자 1240 을 돌려줘, 기록으로 적립해도 화면의 잔액이 움직이지 않았다.
    # 데모 회원의 시작 잔액(`DEMO_OPENING_POINTS`)은 시드가 프로필에 넣는다.
    points = profile.activity_points if profile is not None else 0

    return UserHealth(
        profile=HealthProfileBrief(
            id=current_user.id, name=current_user.name, email=current_user.email
        ),
        activity_points=points,
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
        daily_calories=p.daily_calories if p else None,
        daily_sodium_mg=p.daily_sodium_mg if p else None,
        daily_sugar_g=p.daily_sugar_g if p else None,
        daily_carbs_g=p.daily_carbs_g if p else None,
        daily_protein_g=p.daily_protein_g if p else None,
        effective_daily_protein_g=effective_protein_g(p),
        daily_fat_g=p.daily_fat_g if p else None,
        weekly_workout_goal=p.weekly_workout_goal if p else None,
        weekly_exercise_minutes_goal=(p.weekly_exercise_minutes_goal if p else None),
        weekly_burn_goal=p.weekly_burn_goal if p else None,
        daily_burn_kcal=p.daily_burn_kcal if p else None,
        weekly_cardio_minutes=p.weekly_cardio_minutes if p else None,
        weekly_strength_sets=p.weekly_strength_sets if p else None,
        weekly_flexibility_minutes=(p.weekly_flexibility_minutes if p else None),
        onboarded=p.onboarded if p else False,
        onboarding_skipped=bool(p.onboarding_skipped) if p else False,
        has_password=bool(user.hashed_password),
        focus_changed_by=p.focus_changed_by if p else None,
        focus_changed_at=p.focus_changed_at if p else None,
        notes_changed_by=p.notes_changed_by if p else None,
        notes_changed_at=p.notes_changed_at if p else None,
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
    name_before = user.name
    if "name" in data and data["name"] is not None:
        user.name = data.pop("name")
        # 담당 트레이너가 있는데 첫 설정에서 이름을 고쳤다면 알린다(#2065).
        name_change.record_member_rename(db, user, before=name_before)
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


@router.post("/users/me/onboarding/skip", response_model=ProfileView)
def skip_onboarding(
    user: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> ProfileView:
    """첫 설정 건너뛰기를 계정에 남긴다(#2855).

    건너뛴 회원은 다음 로그인·세션 복구 때 첫 설정 화면으로 다시 가지 않는다.
    값은 아무것도 저장하지 않는다 — 건너뛴 것이지 끝낸 것이 아니라 `onboarded`
    는 그대로다. 여러 번 불러도 결과가 같다.
    """
    profile = _get_or_create_profile(db, user)
    profile.onboarding_skipped = True
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
        # 대소문자만 다른 주소도 같은 이메일이다(#2816). `new_email` 은 스키마가
        # 이미 소문자로 맞췄다.
        dup = db.scalar(
            select(User).where(
                func.lower(User.email) == new_email, User.id != user.id
            )
        )
        if dup is not None:
            raise HTTPException(status_code=409, detail="이미 사용 중인 이메일입니다.")
        user.email = new_email
        # 위 중복 조회는 빠른 실패용이다. 같은 새 이메일로 바꾸는 요청(또는 같은
        # 이메일 가입)이 겹치면 둘 다 조회를 통과하고 `users.email` 유일 제약에서
        # 만난다 — 500 대신 조회로 막았을 때와 같은 409 로 옮긴다(#2911). 아래
        # 조회의 자동 flush 에서 터지지 않도록 이메일만 여기서 먼저 내려 보낸다.
        try:
            db.flush()
        except IntegrityError:
            db.rollback()
            raise HTTPException(
                status_code=409, detail="이미 사용 중인 이메일입니다."
            ) from None
    if data.get("name") is not None:
        name_before = user.name
        user.name = data["name"]
        # 트레이너 알림함에는 옛 이름의 알림이 그대로 남는다 — 바뀐 사실을 한 번
        # 알려 목록의 새 이름과 잇는다(#2065).
        name_change.record_member_rename(db, user, before=name_before)

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
    request: Request,
    payload: AccountDeleteRequest | None = None,
) -> dict:
    """회원 탈퇴. 예약 좌석을 복구한 뒤 프로필·식단·운동·일정·알림·
    소셜계정·개인 코치문서를 함께 삭제한다. 대기 중 상담 요청은 요청을 받은
    트레이너에게 취소를 알린 뒤 함께 지운다(#1632).

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
    # 대기 중인 상담이 잡고 있던 자리도 풀어 준다 — 요청 행은 CASCADE 로 사라져도
    # 자리는 남아 잠긴 채가 된다(#1873).
    consultation_service.release_holds_for_account_deletion(db, user.id)
    # 대기 요청도 CASCADE 로 사라진다 — 요청을 받은 트레이너(담당 제외)에게 지우기
    # 전에 알린다. 이름·희망 날짜는 지금 읽어 둔다(#1632).
    consultation_service.notify_trainers_of_account_deletion(db, user)
    # 담당 링크는 회원과 함께 CASCADE 로 사라진다 — 지우기 전에 담당 트레이너에게
    # 알린다. 알림은 트레이너 계정에 달려 탈퇴 뒤에도 남는다(#2174).
    member_departure.notify_trainer(db, user, reason="withdrawn")
    # 동의 종료·탈퇴를 감사 기록으로 남긴다 — 링크와 계정이 사라져도 남는다(#2830).
    data_consent_service.stage_account_withdrawal(db, user, ip=client_ip(request))
    # 채팅 첨부의 바이트는 DB 밖에 있어 CASCADE 가 닿지 않는다 — 행이 사라지기
    # 전에 목록을 잡아 두고, 커밋이 끝난 뒤에 지운다(#2817).
    attachments = attachment_cleanup.files_in_threads(db, member_id=user.id)
    db.delete(user)
    db.commit()
    attachment_cleanup.purge(attachments)
    return {"status": "deleted"}


@router.post(
    "/users/me/password",
    status_code=200,
    response_model=PasswordChanged,
    dependencies=[Depends(rate_limit("member-password-change"))],
)
def change_my_password(
    request: Request,
    payload: MemberPasswordChange,
    user: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> PasswordChanged:
    """회원 비밀번호 변경(#2824). 트레이너 `POST /trainer/me/password` 와 같은 규약.

    현재 비밀번호가 맞아야 하고 같은 값으로는 바꿀 수 없다. 바꾸면 토큰 세대가
    올라 다른 기기의 접근·refresh 토큰이 모두 끊기고(#2766), 요청한 기기는 응답의
    새 토큰 한 쌍으로 이어 쓴다.

    소셜 로그인 전용 계정(비밀번호 없음)은 409 다 — 확인할 현재 비밀번호가 없다.
    현재 비밀번호 불일치는 401 이 아니라 400 이다. 토큰은 유효하므로 앱이
    로그아웃으로 오인하면 안 된다. 틀린 비밀번호를 연달아 맞혀 보는 것은 IP 별
    rate limit 이 막는다.
    """
    if not user.hashed_password:
        raise HTTPException(
            status_code=409,
            detail="소셜 로그인 계정은 비밀번호가 없어 바꿀 수 없습니다.",
        )
    if not verify_password(payload.current_password, user.hashed_password):
        audit(
            db,
            event="auth.password_change",
            user_id=user.id,
            ip=client_ip(request),
            success=False,
        )
        raise HTTPException(status_code=400, detail="현재 비밀번호가 일치하지 않습니다.")
    if verify_password(payload.new_password, user.hashed_password):
        raise HTTPException(status_code=400, detail="현재와 다른 비밀번호를 입력해 주세요.")
    user.hashed_password = hash_password(payload.new_password)
    # 비밀번호와 세대는 한 트랜잭션으로 — 하나만 반영되면 옛 토큰이 살아남거나
    # 비밀번호는 그대로인데 모든 기기가 끊긴다.
    auth_tokens.bump_version(user)
    db.commit()
    audit(
        db,
        event="auth.password_change",
        user_id=user.id,
        ip=client_ip(request),
        success=True,
    )
    tokens = auth_tokens.issue_token_pair(user)
    return PasswordChanged(
        access_token=tokens.access_token, refresh_token=tokens.refresh_token
    )


# ---- 인증 (Stage 4 대비, 지금도 동작) ----


def _check_register_email(email: str) -> None:
    """같은 이메일 가입 시도 상한(#2913).

    가입은 이미 있는 이메일에 409 를 주므로 IP 한도만으로는 IP 를 바꿔 가며 특정
    이메일의 가입 여부를 계속 물을 수 있다. 이메일 단위로 한 시간에 몇 번까지만
    받는다. 성공·실패를 가리지 않고 센다 — 세는 기준이 결과에 따라 갈리면 그 차이로
    다시 가입 여부가 드러난다. 문구(409·429)는 그대로라 화면 변화는 없다.
    """
    check_key(
        register_email_key(email),
        get_settings().register_per_email_per_hour,
        3600.0,
    )


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
    _check_register_email(payload.email)
    # `payload.email` 은 스키마가 소문자로 맞췄다. 대소문자만 다른 기존 주소도
    # 같은 이메일로 보고 거절한다(#2816).
    exists = db.scalar(select(User).where(func.lower(User.email) == payload.email))
    if exists:
        audit(
            db,
            event="auth.register",
            ip=client_ip(request),
            success=False,
            detail=masked_email(payload.email),
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
    # 가입 화면에서 체크한 동의를 계정과 **한 트랜잭션**으로 남긴다(#2819).
    # 나눠 커밋하면 동의 기록 없는 계정이 남는다. 목록을 보내지 않은 옛 빌드는
    # 기록 없이 만들어지고, 로그인 직후 동의 화면을 거친다.
    if payload.consents is not None:
        db.flush()
        signup_consent.record(db, user.id, payload.consents)
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
    return UserMe(id=user.id, name=user.name, email=user.email, role=user.role)


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
    """트레이너 계정을 만든다. (#475)

    `/auth/register` 와 나누는 이유: 그쪽은 `role='member'` 를 만든다. 한 엔드포인트에
    역할 분기를 넣으면 요청 필드 하나로 역할이 바뀌는 경로가 생기기 쉽다.

    소속 헬스장은 여기서 정하지 않는다 — 가입 뒤 `PUT /trainer/me/gym` 으로 고른다
    (#1627). 소속이 없는 동안에는 상담 대상이 아니다(#443·#451).

    회원 가입과 같은 rate limit 버킷을 쓴다(IP·이메일 둘 다).
    """
    _check_register_email(payload.email)
    try:
        trainer = trainer_signup_service.register_trainer(db, payload)
    except trainer_signup_service.TrainerEmailTaken as exc:
        audit(
            db,
            event="auth.trainer_register",
            ip=client_ip(request),
            success=False,
            detail=masked_email(payload.email),
        )
        raise HTTPException(status_code=409, detail=str(exc)) from exc

    audit(
        db,
        event="auth.trainer_register",
        user_id=trainer.id,
        ip=client_ip(request),
        success=True,
    )
    return UserMe(
        id=trainer.id, name=trainer.name, email=trainer.email, role=trainer.role
    )


def _login_lock_key(username: str) -> str:
    """로그인 실패 잠금 버킷 키. 대소문자·앞뒤 공백만 다른 입력은 같은 계정이다."""
    return f"login-fail:{normalize_email(username)}"


@router.post(
    "/auth/login",
    response_model=LoginToken,
    dependencies=[Depends(rate_limit("auth-login"))],
)
def login(
    request: Request,
    form: Annotated[OAuth2PasswordRequestForm, Depends()],
    db: Annotated[Session, Depends(get_db)],
) -> LoginToken:
    """이메일·비밀번호 로그인.

    IP 한도(`auth-login`)에 더해 **이메일 단위 실패 잠금**을 건다(#2815). IP 를
    바꿔 가며 한 계정을 노리면 IP 버킷은 매번 새로 시작하지만, 이메일 버킷은 한
    곳에 모인다. 잠금 판정은 비밀번호 확인보다 먼저 한다 — 잠긴 동안에는 맞는
    비밀번호인지 여부도 응답에 드러나지 않는다. 없는 이메일도 똑같이 세고 잠가
    가입 여부가 갈리지 않게 한다.
    """
    settings = get_settings()
    lock_key = _login_lock_key(form.username)
    lock_window = float(settings.login_lockout_seconds)
    ensure_unlocked(lock_key, settings.login_max_failures, lock_window)
    # 가입이 소문자로 저장하므로 입력도 같은 규칙으로 맞춰 찾는다(#2816) — 모바일
    # 키보드가 첫 글자를 대문자로 바꿔도 같은 계정이다.
    user = db.scalar(
        select(User).where(func.lower(User.email) == normalize_email(form.username))
    )
    if (
        not user
        or not user.is_active
        or not verify_password(form.password, user.hashed_password)
    ):
        record_failure(lock_key, lock_window)
        audit(
            db,
            event="auth.login",
            ip=client_ip(request),
            success=False,
            detail=masked_email(form.username),
        )
        raise HTTPException(
            status_code=401, detail="이메일 또는 비밀번호가 올바르지 않습니다."
        )
    clear_failures(lock_key)
    audit(db, event="auth.login", user_id=user.id, ip=client_ip(request), success=True)
    return auth_tokens.issue_login_tokens(db, user)


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
    if not auth_tokens.is_current(user, claims.token_version):
        # 비밀번호 변경 전에 발급된 refresh 토큰(#2766). 다른 기기에 남은 세션이다 —
        # 회전해 주면 비밀번호를 바꾼 의미가 없다. 폐기 표에도 적어 같은 토큰이
        # 다시 와도 같은 결과가 되게 한다(세대 칸이 되돌려져도 살아나지 않게).
        token_revocation.revoke(
            db, jti=claims.jti, user_id=user.id, expires_at=claims.expires_at
        )
        audit(
            db,
            event="auth.refresh_stale",
            user_id=user.id,
            ip=client_ip(request),
            success=False,
        )
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
    # 웹으로 발급된 토큰은 헤더가 없어도 웹 수명으로 회전한다(#2828).
    return auth_tokens.issue_token_pair(user, web=claims.web)


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


# ---- 비밀번호 재설정 (#2824) ----


@router.post(
    "/auth/password-reset/request",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=PasswordResetRequested,
    dependencies=[Depends(rate_limit("auth-password-reset-request"))],
)
def request_password_reset(
    payload: PasswordResetRequest,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
) -> PasswordResetRequested:
    """재설정 코드를 메일로 보낸다. 회원·트레이너 공용.

    **응답은 계정 존재 여부와 무관하게 같다**(202). 가입되지 않은 이메일, 쉬는
    계정, 소셜 로그인 전용 계정에는 아무것도 보내지 않지만 응답으로는 알 수 없다.

    시도 제한은 두 겹이다. IP 별 분당 한도(`auth-password-reset-request`)와,
    한 이메일로 보내는 메일 수 한도(`PASSWORD_RESET_EMAIL_PER_WINDOW`). 뒤의 것은
    여러 IP 에서 한 사람에게 메일을 쏟아붓는 것을 막는다 — 계정이 없는 주소도 똑같이
    세므로 429 로 가입 여부가 드러나지 않는다.

    서버에 메일 발송 수단이 없으면(운영인데 SMTP 설정이 비었을 때) 503 이다.
    """
    settings = get_settings()
    if settings.rate_limit_enabled:
        limiter.check(
            f"pw-reset-email:{payload.email.lower()}",
            settings.password_reset_email_per_window,
            settings.password_reset_email_window_minutes * 60.0,
        )
    try:
        issued = password_reset.request_reset(
            db,
            payload.email,
            now=clock.now(),
            settings=settings,
            locale=get_request_locale(request),
        )
    except password_reset.ResetUnavailable:
        raise HTTPException(
            status_code=503,
            detail="지금은 비밀번호 재설정 메일을 보낼 수 없습니다. 고객센터로 문의해 주세요.",
        ) from None
    audit(
        db,
        event="auth.password_reset_request",
        user_id=issued.user_id if issued else None,
        ip=client_ip(request),
        # 감사 로그에는 실제로 코드를 만들었는지 남긴다 — 응답과 달리 운영자만 본다.
        success=issued is not None,
    )
    return PasswordResetRequested(
        expires_in_minutes=settings.password_reset_token_minutes
    )


@router.post(
    "/auth/password-reset/confirm",
    response_model=PasswordResetDone,
    dependencies=[Depends(rate_limit("auth-password-reset-confirm"))],
)
def confirm_password_reset(
    payload: PasswordResetConfirm,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
) -> PasswordResetDone:
    """코드와 새 비밀번호로 비밀번호를 바꾼다.

    코드가 없거나 만료됐거나 이미 쓰였으면 모두 400 `invalid_reset_token` 하나다 —
    어느 쪽인지 갈라 알려 줄 이유가 없다. 바꾸면 토큰 세대가 올라 모든 기기의
    세션이 끊긴다(#2766). 새 토큰은 주지 않으므로 새 비밀번호로 다시 로그인한다.
    """
    try:
        user = password_reset.confirm_reset(
            db, payload.token, payload.new_password, now=clock.now()
        )
    except password_reset.InvalidResetCode:
        audit(
            db,
            event="auth.password_reset_confirm",
            ip=client_ip(request),
            success=False,
        )
        raise HTTPException(
            status_code=400,
            detail={
                "code": "invalid_reset_token",
                "message": "재설정 코드가 올바르지 않거나 만료되었습니다. 다시 요청해 주세요.",
            },
        ) from None
    audit(
        db,
        event="auth.password_reset_confirm",
        user_id=user.id,
        ip=client_ip(request),
        success=True,
    )
    return PasswordResetDone()
