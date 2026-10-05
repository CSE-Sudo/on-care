"""트레이너 도메인 — 트레이너 프로필과 계정 삭제."""
from __future__ import annotations

import json

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.models import (
    Place, TrainerClient, TrainerProfile, TrainerReservation, TrainerReservationSlot, User,
)
from app.schemas.trainer_api import (
    TrainerGymOut, TrainerMe,
)
from app.services import (
    diet_coach_inputs,
    notification_service,
    notification_templates,
    points_coupon_service,
)


def delete_trainer_account(db: Session, trainer: User) -> None:
    """트레이너 탈퇴. 담당 회원에게 알린 뒤 계정을 지운다. (#505)

    **담당 회원이 남아 있어도 막지 않는다.** 막으면 담당이 있는 트레이너는 계정을
    영영 지울 수 없고, 그만두는 사람에게 "회원을 먼저 다 정리하라" 고 요구하는 것은
    현실적이지 않다. 대신 회원이 모르게 사라지지 않도록 알림을 남긴다 — 회원 앱의
    '내 담당 코치'가 어느 날 조용히 비어 있으면 앱이 고장 난 것으로 읽힌다.

    삭제 순서가 중요하다. `trainer_reservations` 는 회원·슬롯·일정을 모두
    **RESTRICT** 로 참조한다. 슬롯과 일정은 트레이너 삭제 시 CASCADE 로 지워지므로,
    예약 행을 먼저 치우지 않으면 그 CASCADE 가 FK 에서 막힌다.

    나머지(프로필·채팅·루틴·일정·슬롯·이력·알림)는 `users.id` CASCADE 가 처리한다.
    상담 요청의 `trainer_id`·`decided_by` 는 SET NULL 이라 요청 이력은 남는다.
    """

    # 이 트레이너의 슬롯에 걸린 예약을 먼저 치운다. 좌석을 되돌릴 필요는 없다 —
    # 슬롯 자체가 함께 사라진다.
    reservations = db.scalars(
        select(TrainerReservation)
        .join(
            TrainerReservationSlot,
            TrainerReservationSlot.id == TrainerReservation.slot_id,
        )
        .where(TrainerReservationSlot.trainer_id == trainer.id)
        .order_by(TrainerReservation.id)
        .with_for_update()
    ).all()
    booked_member_ids = {row.member_id for row in reservations}
    for reservation in reservations:
        db.delete(reservation)
    # RESTRICT 자식을 먼저 비운 뒤에야 트레이너 삭제의 CASCADE 가 성립한다.
    db.flush()

    # 지금 담당 중인 회원의 PT 재등록 쿠폰은 쓸 트레이너가 사라지므로 취소하고
    # 포인트를 돌려준다(#1787). 과거 담당(휴면 링크) 회원은 이미 해제 때 처리됐다.
    #
    # 탈퇴 알림도 이 회원들에게만 간다(#3024). 담당이 이미 끝난 회원에게 "담당
    # 트레이너 연결이 해제되었어요" 를 보내면 오래전에 끝난 관계를 새 소식으로 읽는다.
    active_member_ids = list(
        db.scalars(
            select(TrainerClient.member_id).where(
                TrainerClient.trainer_id == trainer.id,
                TrainerClient.active.is_(True),
            )
        ).all()
    )
    for member_id in active_member_ids:
        points_coupon_service.cancel_renewal_coupons(db, member_id)
        # 탈퇴한 트레이너의 메시지로 만든 식단 AI 보관물도 내려놓는다(#1631).
        diet_coach_inputs.forget_trainer_notes(db, member_id)

    # 이름이 없으면 틀이 대신 적는 말(`트레이너`)을 고른다(#2302).
    trainer_name = trainer.name or ""
    for member_id in active_member_ids:
        notification_service.queue(
            db,
            member_id=member_id,
            kind=notification_service.PT_LINK_NOTICE,
            # 새 트레이너를 찾는 화면으로 보낸다.
            category=notification_service.MEMBER_CONSULTATION,
            template=notification_templates.MEMBER_TRAINER_LEFT,
            template_args={"trainer_name": trainer_name},
        )
    # 예약만 있고 지금 담당은 아닌 회원에게도 알린다 — 잡아 둔 수업이 사라진다.
    # 담당이 끝난 과거 회원이라도 예약이 남아 있으면 여기서 받는다(#3024).
    for member_id in sorted(booked_member_ids - set(active_member_ids)):
        notification_service.queue(
            db,
            member_id=member_id,
            kind=notification_service.PT_LINK_NOTICE,
            category=notification_service.MEMBER_SCHEDULE,
            template=notification_templates.MEMBER_TRAINER_LEFT_BOOKING,
            template_args={"trainer_name": trainer_name},
        )

    db.delete(trainer)
    db.commit()


# ---- 트레이너 프로필 ----


def _certifications(profile: TrainerProfile) -> list[str]:
    """자격증 JSON 을 방어적으로 디코드. 깨진 값은 빈 목록으로 (프로필 화면이
    500 으로 죽는 것보다 낫다)."""
    try:
        certs = json.loads(profile.certifications_json) if profile.certifications_json else []
    except json.JSONDecodeError:
        return []
    if not isinstance(certs, list) or not all(isinstance(c, str) for c in certs):
        return []
    return certs


def build_trainer_me(db: Session, trainer: User, profile: TrainerProfile) -> TrainerMe:
    """`GET /trainer/me` 응답. 조회와 수정이 같은 표현을 쓰도록 분리."""
    # 좌표는 소속 장소에만 있다 — 호환 문자열(gym_*)처럼 프로필에 복사해 두지 않는다.
    place = db.get(Place, profile.gym_id) if profile.gym_id else None
    return TrainerMe(
        id=trainer.id,
        name=trainer.name,
        email=trainer.email,
        phone=profile.phone,
        specialty=profile.specialty,
        career=f"{profile.career_years}년",
        intro=profile.intro,
        certifications=_certifications(profile),
        gym=TrainerGymOut(
            id=profile.gym_id,
            name=profile.gym_name,
            address=profile.gym_address,
            hours=profile.gym_hours,
            phone=profile.gym_phone,
            lat=place.lat if place else None,
            lng=place.lng if place else None,
        ),
        is_admin=bool(trainer.is_admin),
        has_password=bool(trainer.hashed_password),
    )


#: `TrainerMeUpdate` 가 받는 호환용 헬스장 문자열. 소속(`gym_id`)에서만 파생되므로
#: 직접 수정할 수 없다(#452, #2543).
GYM_TEXT_FIELDS = ("gym_name", "gym_address", "gym_hours", "gym_phone")


class GymTextNotEditable(Exception):
    """호환 문자열을 직접 바꾸려 한 경우. (#452, #2543)

    예전에는 소속이 없는 프로필에 한해 직접 적게 해 줬다. 그렇게 적은 이름은
    `gym_id` 가 비어 회원에게 노출되지 않는데도 트레이너 화면에는 소속이 있는
    것처럼 보였다. 이제 소속은 헬스장 검색(`/trainer/gyms/search`)으로만 정한다.
    """


def update_trainer_profile(
    db: Session, trainer: User, profile: TrainerProfile, fields: dict
) -> TrainerMe:
    """보낸 필드만 반영한다. 자격증은 통째로 교체(부분 병합은 순서가 모호하다).

    헬스장 문자열이 하나라도 오면 `GymTextNotEditable` 을 올리고 라우터가 409 로
    돌려준다 — 함께 온 다른 필드도 반영하지 않는다(일부만 저장되면 클라이언트가
    무엇이 저장됐는지 모른다).
    """
    if any(f in fields for f in GYM_TEXT_FIELDS):
        raise GymTextNotEditable

    if "certifications" in fields:
        certs = [c.strip() for c in (fields["certifications"] or []) if c.strip()]
        profile.certifications_json = json.dumps(certs, ensure_ascii=False)
    for column in ("phone", "specialty", "career_years", "intro"):
        if column in fields:
            setattr(profile, column, fields[column])
    db.commit()
    db.refresh(profile)
    return build_trainer_me(db, trainer, profile)
