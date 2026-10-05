"""트레이너 도메인 — 소속 헬스장. (#452)"""
from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.models import (
    GymProfile, Place, TrainerProfile, User,
)
from app.schemas.trainer_api import (
    TrainerMe,
)
from app.services.trainer.profile import (
    build_trainer_me,
)


# ---- 소속 헬스장 (#452) ----


def _apply_gym_texts(profile: TrainerProfile, place: Place | None, gym: GymProfile | None) -> None:
    """호환 문자열을 소속에서 파생시킨다 — 소속이 진실이고 문자열은 그 사본이다.

    트레이너 앱은 아직 `gym.{name,address,hours,phone}` 만 읽으므로, 소속을 바꿔도
    문자열이 그대로면 화면에는 예전 헬스장이 남는다. 해제(place=None)면 비운다 —
    떠난 헬스장의 이름을 남겨 두면 회원 쪽 코치 카드가 그 값으로 폴백한다
    (`_member_gym_out`).
    """
    if place is None:
        profile.gym_name = ""
        profile.gym_address = ""
        profile.gym_hours = ""
        profile.gym_phone = ""
        return
    # places.name(200) 이 trainer_profiles.gym_name(100) 보다 길다 — 넘치면 DB 가 막는다.
    profile.gym_name = place.name[:100]
    profile.gym_address = place.address[:300]
    # 영업시간·전화는 헬스장 부가 정보(GymProfile)에만 있다. 카카오에서 발견한
    # 헬스장은 부가 정보가 없어 빈 값이 정상이다.
    profile.gym_hours = (gym.weekday_hours if gym else "")[:50]
    profile.gym_phone = (gym.phone if gym else "")[:20]


def set_trainer_gym(
    db: Session, trainer: User, profile: TrainerProfile, gym_id: str
) -> TrainerMe | None:
    """소속 헬스장을 설정·변경한다. 유효한 헬스장이 아니면 None(라우터 404).

    `places` 에 있고 category 가 'fitness' 인 곳만 받는다 — 상담 대상 검증
    (`consultation_service._validate_target`)·헬스장 디렉터리와 같은 조건이라야
    소속을 설정한 트레이너가 회원 화면에 제대로 뜬다(#451, #443).
    """
    place = db.scalar(
        select(Place).where(Place.id == gym_id, Place.category == "fitness")
    )
    if place is None:
        return None

    profile.gym_id = place.id
    _apply_gym_texts(profile, place, db.get(GymProfile, place.id))
    db.commit()
    db.refresh(profile)
    return build_trainer_me(db, trainer, profile)


def clear_trainer_gym(db: Session, trainer: User, profile: TrainerProfile) -> TrainerMe:
    """소속 해제. 원래 없었어도 성공한다 — 해제는 두 번 눌러도 오류가 아니다.

    회원↔헬스장 링크(`member_gyms`)는 건드리지 않는다. 회원이 직접 연결한 헬스장은
    트레이너가 이적해도 회원의 선택으로 남는다(#444).
    """
    profile.gym_id = None
    _apply_gym_texts(profile, None, None)
    db.commit()
    db.refresh(profile)
    return build_trainer_me(db, trainer, profile)
