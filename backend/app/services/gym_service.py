"""헬스장·트레이너 디렉터리 조회. (#324)

헬스장은 `places`(category='fitness') 이고 부가 정보는 `gym_profiles` 에 있다.
프로필이 없는 헬스장(기존 데모 시드, 카카오 발견분)도 목록에는 나와야 하므로 outer
조인으로 읽고 빈 값을 채운다.
"""
from __future__ import annotations

import json
import math

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.models import GymProfile, MemberGym, Place, TrainerProfile, User
from app.schemas.gym_api import GymOut, TrainerOut
from app.services import points_coupon_service, trainer_recommendation


def _haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> int:
    """`places.py` 의 `_haversine_m` 과 같은 계산(절삭)."""
    r = 6371000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return int(r * 2 * math.asin(math.sqrt(a)))


def _tags(profile: GymProfile | None) -> list[str]:
    if profile is None or not profile.tags_json:
        return []
    try:
        parsed = json.loads(profile.tags_json)
    except json.JSONDecodeError:
        return []
    return [str(t) for t in parsed] if isinstance(parsed, list) else []


def _to_gym(
    place: Place, profile: GymProfile | None, lat: float | None, lng: float | None
) -> GymOut:
    distance_km = 0.0
    if lat is not None and lng is not None and place.lat is not None and place.lng is not None:
        distance_km = _haversine_m(lat, lng, place.lat, place.lng) / 1000
    return GymOut(
        id=place.id,
        name=place.name,
        address=place.address,
        distance_km=distance_km,
        # 평점 없음을 0 으로 내린다 — 프론트 Gym.rating 이 non-null 이고 0 이면
        # 뱃지를 감추기로 이미 합의돼 있다(#329).
        rating=profile.rating if profile and profile.rating is not None else 0.0,
        tags=_tags(profile),
        weekday_hours=(profile.weekday_hours or None) if profile else None,
        weekend_hours=(profile.weekend_hours or None) if profile else None,
        phone=(profile.phone or None) if profile else None,
        lat=place.lat,
        lng=place.lng,
        is_partner=bool(profile.is_partner) if profile else False,
    )


def list_gyms(
    db: Session,
    *,
    lat: float | None = None,
    lng: float | None = None,
    partner_only: bool = False,
) -> list[GymOut]:
    """헬스장 목록. 좌표를 주면 거리순, 아니면 이름순."""
    query = (
        select(Place, GymProfile)
        .outerjoin(GymProfile, GymProfile.place_id == Place.id)
        .where(Place.category == "fitness")
    )
    if partner_only:
        query = query.where(GymProfile.is_partner.is_(True))

    gyms = [_to_gym(place, profile, lat, lng) for place, profile in db.execute(query)]
    if lat is not None and lng is not None:
        # 좌표를 모르는 헬스장은 distance_km 가 0 이라 그냥 정렬하면 '가장 가까운 곳'
        # 으로 맨 앞에 온다. 뒤로 보내고 그 안에서는 이름순으로 둔다.
        gyms.sort(
            key=lambda g: (
                g.lat is None or g.lng is None,
                g.distance_km,
                g.name,
            )
        )
    else:
        gyms.sort(key=lambda g: g.name)
    return gyms


def get_gym(
    db: Session, gym_id: str, *, lat: float | None = None, lng: float | None = None
) -> GymOut | None:
    row = db.execute(
        select(Place, GymProfile)
        .outerjoin(GymProfile, GymProfile.place_id == Place.id)
        .where(Place.id == gym_id, Place.category == "fitness")
    ).first()
    if row is None:
        return None
    place, profile = row
    return _to_gym(place, profile, lat, lng)


# ---- 회원의 내 헬스장 (#444) ----

def get_member_gym_id(db: Session, member_id: str) -> str | None:
    """회원이 직접 연결한 헬스장 id. 없으면 None.

    담당 트레이너의 소속에서 파생하지 않는다 — 트레이너만 해제해도 헬스장은 남아야
    한다. 트레이너 소속으로의 폴백은 호출부(`trainer_service.build_member_coach`)가
    아직 백필되지 않은 데이터를 위해 따로 처리한다.
    """
    return db.scalar(select(MemberGym.gym_id).where(MemberGym.member_id == member_id))


def get_member_gym(
    db: Session, member_id: str, *, lat: float | None = None, lng: float | None = None
) -> GymOut | None:
    """회원의 '내 헬스장' 카드. 연결이 없거나 헬스장이 사라졌으면 None."""
    gym_id = get_member_gym_id(db, member_id)
    return None if gym_id is None else get_gym(db, gym_id, lat=lat, lng=lng)


def unlink_member_gym(db: Session, member_id: str) -> bool:
    """헬스장 연결 해제. 끊었으면 True, 원래 없었으면 False.

    담당 링크와 달리 행을 지운다 — 이 링크를 참조하는 이력이 없다.

    헬스장이 끝나므로 회원의 개인 락커 쿠폰을 취소하고 포인트를 돌려준다(#1787).
    회원 헬스장 링크를 지우는 곳은 여기 하나다.

    **커밋하지 않는다.** 헬스장 해제는 담당 트레이너 해제와 함께 일어나므로
    (`trainer_service.disconnect_member_gym`), 여기서 커밋하면 뒤 단계가 실패했을 때
    헬스장만 끊기고 담당은 남는 반쪽 상태가 된다. 커밋은 호출부가 한 번만 한다.
    """
    link = db.get(MemberGym, member_id)
    if link is None:
        return False
    db.delete(link)
    points_coupon_service.cancel_locker_coupons(db, member_id)
    return True


def _to_trainer(
    user: User, profile: TrainerProfile, *, generated_reason: str = ""
) -> TrainerOut:
    try:
        certs = json.loads(profile.certifications_json or "[]")
    except json.JSONDecodeError:
        certs = []
    return TrainerOut(
        id=user.id,
        gym_id=profile.gym_id,
        name=user.name,
        role=profile.specialty or None,
        # 사람이 쓴 사유가 우선. 생성 문구는 그 자리가 비었을 때만 채운다 — 운영자가
        # 적어 둔 문구가 자동 생성으로 덮이면 큐레이션이 무의미해진다. (#500)
        reason=profile.recommend_reason or generated_reason or None,
        # 앱은 "7년" 문자열을 그대로 렌더한다. 0 이면 표시할 게 없으므로 None.
        career=f"{profile.career_years}년" if profile.career_years else None,
        intro=profile.intro or None,
        certifications=[str(c) for c in certs] if isinstance(certs, list) else [],
    )


def _trainer_query(*, require_gym: bool = True):
    """디렉터리에 노출할 트레이너 — 상담 대상 조건과 같아야 한다. (#451)

    `consultation_service._validate_target` 은 상담 요청 시 트레이너의 소속을
    `places`(category='fitness') 에서 검증한다. 여기서 role·active 만 보면
    소속이 없는 트레이너가 목록·상세에 뜨고, 회원은 상담 신청 단계에서야 404 를
    받는다. 두 곳이 같은 조건을 쓰도록 `places` 를 inner 조인한다.

    따라서 다음 트레이너는 목록·추천·상세 어디에도 나오지 않는다(상세는 404):

    - `gym_id` 가 NULL — 아직 소속이 백필되지 않았거나 해제된 경우.
      `TrainerProfile.gym_id` 는 `places.id` 를 ondelete='SET NULL' 로 참조하므로,
      헬스장이 지워지면 소속은 NULL 이 되고 여기서 함께 빠진다(가리키는 Place 가
      없는 gym_id 는 FK 가 막아 준다).
    - 소속 Place 의 category 가 'fitness' 가 아님 — 병원·약국 같은 다른 장소.

    소속이 빠진 트레이너를 숨기는 쪽을 골랐다. 상담을 걸 수 없는 트레이너를 목록에
    남기면 회원은 고를 수 있는데 마지막 단계에서만 막히고, 트레이너 앱이 소속을
    채우면(#452) 그대로 다시 노출된다.

    `require_gym=False` 는 **이미 담당으로 배정된 트레이너를 그 회원이 읽을 때**만
    쓴다(`get_trainer`). 그 자리는 디렉터리 노출이 아니라 이미 맺어진 관계를 읽는
    것이라 소속 조건이 맞지 않는다. (#691)
    """
    query = (
        select(User, TrainerProfile)
        .join(TrainerProfile, TrainerProfile.trainer_id == User.id)
        .where(
            User.role == "trainer",
            User.is_active.is_(True),
        )
    )
    if not require_gym:
        return query
    return query.join(Place, Place.id == TrainerProfile.gym_id).where(
        Place.category == "fitness"
    )


def list_trainers(db: Session, *, gym_id: str | None = None) -> list[TrainerOut]:
    query = _trainer_query()
    if gym_id is not None:
        query = query.where(TrainerProfile.gym_id == gym_id)
    return [_to_trainer(user, profile) for user, profile in db.execute(query)]


def list_recommended_trainers(
    db: Session, member_id: str | None = None
) -> list[TrainerOut]:
    """홈·운동 탭의 추천 레일.

    `member_id` 가 있고 그 회원에게 쓸 신호가 있으면 **회원별로** 줄 세운다
    (`trainer_recommendation`). 신호가 없으면 — 온보딩 전이거나 만성질환·상담
    이력·내 헬스장이 모두 없는 회원 — 기존 동작 그대로, 운영자가 사유를 적어 둔
    트레이너만 원래 순서로 돌려준다.

    점수를 쓸 때 후보는 `큐레이션된 트레이너 ∪ 점수가 붙은 트레이너` 다. 큐레이션
    목록만 재정렬하면 회원에게 맞는 트레이너가 사유가 없다는 이유만으로 영영
    레일에 못 오르고, 반대로 점수만 쓰면 운영자가 올린 트레이너가 빠진다.

    사유 문구는 **사람이 쓴 것이 우선**이다(`recommend_reason`). 생성 문구는 그
    자리가 비었을 때만 채운다.
    """
    curated_only = _trainer_query().where(TrainerProfile.recommend_reason != "")
    if member_id is None:
        return [_to_trainer(user, profile) for user, profile in db.execute(curated_only)]

    candidates = [(user, profile) for user, profile in db.execute(_trainer_query())]
    ranked = trainer_recommendation.rank(db, member_id, candidates)
    if not ranked:  # 신호 없음 → 기존 동작
        return [_to_trainer(user, profile) for user, profile in db.execute(curated_only)]

    return [
        _to_trainer(user, profile, generated_reason=scored.reason)
        for user, profile, scored in ranked
        if profile.recommend_reason or scored.reason
    ]


def get_trainer(
    db: Session, trainer_id: str, *, viewer_id: str | None = None
) -> TrainerOut | None:
    """트레이너 상세. 디렉터리 조건에 걸리면 None(라우터에서 404).

    예외가 하나 있다. **요청자의 담당 트레이너**는 소속이 비어도 읽을 수 있다.
    `/me/coach` 는 `trainer_clients` 기준으로 담당을 그대로 돌려주는데 상세만 소속
    기준으로 404 를 내면, 회원은 담당이 있다고 표시되면서 그 트레이너를 읽지 못하는
    상태가 된다 — 예약 패널·코치 카드가 통째로 빠진다. 디렉터리 노출 정책(#451)은
    그대로 두고 "내 담당"만 예외로 둔다. (#691)
    """
    row = db.execute(_trainer_query().where(User.id == trainer_id)).first()
    if row is None and viewer_id is not None and _is_my_coach(db, viewer_id, trainer_id):
        row = db.execute(
            _trainer_query(require_gym=False).where(User.id == trainer_id)
        ).first()
    if row is None:
        return None
    user, profile = row
    return _to_trainer(user, profile)


def _is_my_coach(db: Session, member_id: str, trainer_id: str) -> bool:
    """`trainer_id` 가 이 회원의 현재 담당인가 — `/me/coach` 와 같은 기준(활성 링크)."""
    from app.services import trainer_service

    return trainer_service.get_member_trainer_id(db, member_id) == trainer_id
