"""트레이너 운영자 승인. (#2825)

트레이너 웹은 누구나 이메일·비밀번호로 가입하고, 카카오 검색으로 아무 헬스장이나
소속으로 고를 수 있다. 승인 단계가 없으면 그 헬스장과 무관한 사람이 '○○헬스장 소속
트레이너'로 회원 앱에 나오고, 상담 신청 정보와 담당 회원의 식단·운동·신체 기록을
받는다.

그래서 공개 가입으로 생긴 트레이너는 **pending** 에서 시작하고, 운영자가 승인하기
전에는 다음 네 자리에서 빠진다.

- 회원 앱 트레이너 디렉터리·추천·상세(`gym_service._trainer_query`)
- 상담 대상(`consultation_service._validate_target`)
- 담당 요청 발송·수락(`trainer_client_invite_service.invite`/`accept`)
- 회원 연결 코드 확인·사용(`/trainer/pairing-code*`)

가입·로그인·프로필 작성은 그대로 된다. 트레이너는 승인을 기다리는 동안 프로필과
소속을 채워 둘 수 있어야 운영자가 그 내용을 보고 판단할 수 있다.

운영자는 트레이너 웹의 `트레이너 승인` 화면(#3008, 관리자 계정에만 보인다)에서
관리자 엔드포인트(`/admin/trainers*`)로 처리한다. 증빙(자격증 사본) 업로드는 이
단계 밖이다.

승인·반려가 상태를 실제로 바꾸면 트레이너에게 알림을 남긴다(#3010) — 트레이너 웹이
그 알림을 받아 로그인한 채로 승인 상태를 다시 읽는다.
"""
from __future__ import annotations

import json
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.models import Place, TrainerProfile, User
from app.services import notification_service, notification_templates
from app.schemas.trainer_verification import (
    AdminTrainerVerificationOut,
    TrainerVerificationOut,
)

PENDING = "pending"
APPROVED = "approved"
REJECTED = "rejected"

STATUSES = (PENDING, APPROVED, REJECTED)

#: 승인받지 않은 트레이너에게 주는 403 의 `detail.code`. 연결 경로와 담당 회원
#: 기록 열람이 같은 값을 쓴다 — 트레이너 웹이 이 값 하나로 승인 안내를 고른다.
NOT_APPROVED_CODE = "trainer_not_approved"


class TrainerNotFound(Exception):
    """트레이너 계정이 없거나 프로필이 없다 — 404."""


def _now() -> datetime:
    return datetime.now(timezone.utc)


def approved_clause():
    """승인된 트레이너만 남기는 조건. 디렉터리·상담 대상 쿼리가 함께 쓴다."""
    return TrainerProfile.verification_status == APPROVED


def is_approved(db: Session, trainer_id: str) -> bool:
    """`trainer_id` 가 승인된 트레이너인가. 프로필이 없으면 승인 아님."""
    status = db.scalar(
        select(TrainerProfile.verification_status).where(
            TrainerProfile.trainer_id == trainer_id
        )
    )
    return status == APPROVED


def records_locked(db: Session, trainer_id: str) -> bool:
    """반려된 트레이너라 담당 회원의 기록이 잠겼는가(#3009).

    `is_approved` 와 달리 프로필이 없거나 대기면 잠그지 않는다. 대기 트레이너는
    연결 경로가 이미 막혀 담당이 생길 수 없고, 프로필 없이 운영자가 직접 넣은 계정의
    기존 담당은 그대로 열어 둔다. 잠금은 운영자가 명시적으로 반려한 경우뿐이다.
    """
    status = db.scalar(
        select(TrainerProfile.verification_status).where(
            TrainerProfile.trainer_id == trainer_id
        )
    )
    return status == REJECTED


def to_out(profile: TrainerProfile) -> TrainerVerificationOut:
    """`GET /trainer/me` 에 싣는 승인 상태."""
    return TrainerVerificationOut(
        status=profile.verification_status or PENDING,
        decided_at=profile.verification_decided_at,
        note=profile.verification_note or "",
    )


def _require_profile(db: Session, trainer_id: str) -> tuple[User, TrainerProfile]:
    row = db.execute(
        select(User, TrainerProfile)
        .join(TrainerProfile, TrainerProfile.trainer_id == User.id)
        .where(User.id == trainer_id, User.role == "trainer")
    ).first()
    if row is None:
        raise TrainerNotFound("트레이너를 찾을 수 없습니다.")
    return row[0], row[1]


def _admin_out(
    db: Session, user: User, profile: TrainerProfile
) -> AdminTrainerVerificationOut:
    gym_category = (
        db.scalar(select(Place.category).where(Place.id == profile.gym_id))
        if profile.gym_id is not None
        else None
    )
    return AdminTrainerVerificationOut(
        trainer_id=user.id,
        name=user.name,
        email=user.email,
        specialty=profile.specialty,
        career_years=profile.career_years,
        certifications=_certifications(profile),
        gym_id=profile.gym_id,
        gym_name=profile.gym_name,
        gym_address=profile.gym_address,
        gym_is_fitness=gym_category == "fitness",
        status=profile.verification_status,
        decided_at=profile.verification_decided_at,
        decided_by=profile.verification_decided_by,
        note=profile.verification_note or "",
        created_at=user.created_at,
        is_active=bool(user.is_active),
    )


def _certifications(profile: TrainerProfile) -> list[str]:
    try:
        certs = json.loads(profile.certifications_json or "[]")
    except json.JSONDecodeError:
        return []
    return [str(c) for c in certs] if isinstance(certs, list) else []


def list_for_review(
    db: Session, status: str = PENDING
) -> list[AdminTrainerVerificationOut]:
    """운영자가 볼 목록. 기본은 대기 중인 트레이너, `status='all'` 이면 전부."""
    query = (
        select(User, TrainerProfile)
        .join(TrainerProfile, TrainerProfile.trainer_id == User.id)
        .where(User.role == "trainer")
    )
    if status != "all":
        query = query.where(TrainerProfile.verification_status == status)
    query = query.order_by(User.id)
    return [_admin_out(db, user, profile) for user, profile in db.execute(query)]


def _decide(
    db: Session,
    trainer_id: str,
    *,
    status: str,
    admin_id: str,
    note: str,
) -> AdminTrainerVerificationOut:
    user, profile = _require_profile(db, trainer_id)
    changed = profile.verification_status != status
    profile.verification_status = status
    profile.verification_decided_at = _now()
    profile.verification_decided_by = admin_id
    profile.verification_note = note
    if changed:
        _queue_decision_notice(db, trainer_id, status=status, note=note)
    db.commit()
    db.refresh(profile)
    return _admin_out(db, user, profile)


def _queue_decision_notice(
    db: Session, trainer_id: str, *, status: str, note: str
) -> None:
    """승인·반려 알림(#3010). 같은 상태로 다시 처리하면 부르지 않는다 — 사유만
    고친 반려가 알림을 한 건 더 만들면 트레이너는 무엇이 바뀌었는지 모른다."""
    if status == APPROVED:
        notification_service.queue_for_trainer(
            db,
            trainer_id=trainer_id,
            kind=notification_service.TRAINER_VERIFICATION_KIND,
            template=notification_templates.TRAINER_VERIFICATION_APPROVED,
        )
        return
    notification_service.queue_for_trainer(
        db,
        trainer_id=trainer_id,
        kind=notification_service.TRAINER_VERIFICATION_KIND,
        template=notification_templates.TRAINER_VERIFICATION_REJECTED,
        template_args={"has_note": bool(note)},
        body=note,
    )


def approve(
    db: Session, trainer_id: str, *, admin_id: str
) -> AdminTrainerVerificationOut:
    """승인. 반려했던 트레이너도 다시 승인할 수 있다 — 사유는 지운다."""
    return _decide(db, trainer_id, status=APPROVED, admin_id=admin_id, note="")


def reject(
    db: Session, trainer_id: str, *, admin_id: str, reason: str = ""
) -> AdminTrainerVerificationOut:
    """반려. 승인했던 트레이너도 반려할 수 있다.

    반려는 새 연결을 막고, 이미 맺은 담당 회원의 기록 열람도 잠근다(#3009,
    `_require_client`). 담당 관계는 끊지 않는다 — 끊으면 회원 쪽 알림·동의 철회가
    따라오고 되돌릴 수 없다. 다시 승인하면 담당과 열람이 그대로 돌아온다. 관계까지
    끊어야 하면 계정 정지(`account_suspension_service`)를 쓴다.
    """
    return _decide(
        db,
        trainer_id,
        status=REJECTED,
        admin_id=admin_id,
        note=reason.strip(),
    )
