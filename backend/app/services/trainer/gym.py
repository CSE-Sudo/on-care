"""트레이너 도메인 — 소속 헬스장. (#452)"""
from __future__ import annotations

import json

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.models import (
    GymProfile, Place, TrainerProfile, User,
)
from app.schemas.trainer_api import (
    TrainerGymProfileOut, TrainerMe,
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


# ---- 소속 헬스장 부가 정보 (#2700) ----


class NoGymAffiliation(Exception):
    """소속 헬스장이 없어 고칠 헬스장 정보가 없다(라우터 409)."""


def _affiliated_place(db: Session, profile: TrainerProfile) -> Place:
    place = db.get(Place, profile.gym_id) if profile.gym_id else None
    if place is None or place.category != "fitness":
        raise NoGymAffiliation
    return place


def _gym_profile_out(place: Place, gym: GymProfile | None) -> TrainerGymProfileOut:
    # 회원 응답(`gym_service.gym_tags`)과 같은 규칙으로 읽는다 — 깨진 JSON 은 빈 목록.
    from app.services.gym_service import gym_tags

    return TrainerGymProfileOut(
        gym_id=place.id,
        name=place.name,
        weekday_hours=gym.weekday_hours if gym else "",
        weekend_hours=gym.weekend_hours if gym else "",
        phone=gym.phone if gym else "",
        tags=gym_tags(gym),
    )


def get_trainer_gym_profile(
    db: Session, profile: TrainerProfile
) -> TrainerGymProfileOut:
    """소속 헬스장의 부가 정보. 소속이 없으면 `NoGymAffiliation`."""
    place = _affiliated_place(db, profile)
    return _gym_profile_out(place, db.get(GymProfile, place.id))


def update_trainer_gym_profile(
    db: Session, profile: TrainerProfile, fields: dict
) -> TrainerGymProfileOut:
    """소속 헬스장의 영업시간·전화·태그를 고친다. 평점은 건드리지 않는다.

    **소속 트레이너 누구나** 고칠 수 있다 — 헬스장에 대표 트레이너 개념이 없다.
    마지막에 저장한 값이 남는다.

    카카오에서 발견해 등록한 헬스장은 `gym_profiles` 행이 없을 수 있어 없으면
    만든다. 소속을 정할 때 영업시간·전화가 `trainer_profiles` 로 복사되므로
    (`_apply_gym_texts`), 같은 헬스장 소속 트레이너 **모두**의 복사본을 같은
    트랜잭션에서 맞춘다 — 고친 사람만 맞추면 동료의 회원 코치 카드에 옛 값이 남는다.
    """
    place = _affiliated_place(db, profile)
    gym = db.get(GymProfile, place.id)
    if gym is None:
        gym = GymProfile(
            place_id=place.id, rating=None, weekday_hours="", weekend_hours="",
            phone="", tags_json="[]", is_partner=False,
        )
        db.add(gym)

    for key in ("weekday_hours", "weekend_hours", "phone"):
        if key in fields:
            setattr(gym, key, fields[key])
    if "tags" in fields:
        gym.tags_json = json.dumps(fields["tags"], ensure_ascii=False)
    db.flush()

    colleagues = db.scalars(
        select(TrainerProfile).where(TrainerProfile.gym_id == place.id)
    ).all()
    for colleague in colleagues:
        _apply_gym_texts(colleague, place, gym)
    db.commit()
    db.refresh(gym)
    return _gym_profile_out(place, gym)
