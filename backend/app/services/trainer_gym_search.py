"""트레이너 소속 헬스장 찾기 — 카카오 장소 검색으로 고른다. (#2543)

트레이너는 `places` 의 fitness 장소에 소속돼야 회원 앱 헬스장 찾기·상담 신청에
나온다(#443·#451). 그런데 `places` 를 채우는 길이 시드뿐이라, 목록에 없는 헬스장의
트레이너는 헬스장 이름을 직접 적었고 그 이름은 `gym_id` 가 비어 회원에게 보이지
않았다. 여기서는 실제 장소를 검색해 고르게 하고, 고른 순간 `places` 에 넣는다 —
"목록에 들어가는 것 = 카카오에 있는 실제 헬스장"이 규칙이다.

**장소 id 는 카카오 장소 id 를 그대로 쓴다.** 시드의 카카오 발견 헬스장(`seed_gyms`
`_DISCOVERED_GYMS`)과 같은 규칙이라, 같은 실제 헬스장은 기본키 하나로 모인다 —
두 트레이너가 같은 곳을 골라도 행이 둘 생기지 않는다.

**`async` 함수 안의 DB 작업은 스레드풀로 넘긴다(#2835).** 카카오 호출만 `await`
하고, 동기 세션 조회·커밋은 `run_in_threadpool` 로 돌려 이벤트 루프를 막지 않는다.
"""
from __future__ import annotations

import logging

from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.core.config import get_settings
from app.models.models import GymProfile, Place, TrainerProfile, User
from app.schemas.trainer_api import TrainerGymCandidate, TrainerMe
from app.services.trainer import gym as trainer_gym_service
from app.services.places import kakao

logger = logging.getLogger(__name__)

#: 등록된 헬스장 중 이름이 맞는 것을 몇 개까지 먼저 보일지. 카카오 결과(최대 15)와
#: 합쳐도 한 화면에서 훑을 수 있는 길이로 둔다.
_REGISTERED_LIMIT = 10


class GymLookupUnavailable(Exception):
    """카카오 검색을 쓸 수 없어 새 헬스장을 확인할 수 없다 — 라우터 503."""


def kakao_enabled() -> bool:
    settings = get_settings()
    if settings.places_provider == "seed":
        return False
    return bool(settings.kakao_rest_api_key)


def _registered_matches(db: Session, query: str) -> list[Place]:
    """이미 `places` 에 있는 헬스장 중 이름·주소가 검색어를 포함하는 곳.

    카카오에 없는 제휴 시드 헬스장도 고를 수 있어야 하고, 카카오 키가 없는
    환경(로컬·CI)에서는 이것이 유일한 결과다.
    """
    pattern = f"%{query}%"
    return list(db.scalars(
        select(Place)
        .where(
            Place.category == "fitness",
            or_(Place.name.ilike(pattern), Place.address.ilike(pattern)),
        )
        .order_by(Place.name)
        .limit(_REGISTERED_LIMIT)
    ))


async def search(
    db: Session, query: str, lat: float | None, lng: float | None
) -> list[TrainerGymCandidate]:
    """등록된 헬스장을 먼저, 그 뒤에 카카오 결과를 붙인다.

    카카오 결과가 이미 등록된 곳이면 `registered=True` 로 바꿔 한 번만 싣는다 —
    같은 헬스장이 두 줄로 나오면 어느 쪽을 골라야 하는지 헷갈린다. 카카오 호출이
    실패하면 등록된 결과만 돌려준다(검색 자체가 막히면 소속을 바꿀 수 없다).
    """
    out = await run_in_threadpool(_registered_candidates, db, query)
    seen = {c.id for c in out}

    if not kakao_enabled():
        return out

    settings = get_settings()
    try:
        found = await kakao.search_gyms(
            query, lat, lng,
            api_key=settings.kakao_rest_api_key,
            timeout=settings.kakao_timeout_seconds,
        )
    except Exception as exc:  # noqa: BLE001 — 외부 API 실패가 검색을 깨지 않도록
        # 예외 repr 에 좌표가 든 요청 URL 이 들어갈 수 있어 타입만 남긴다.
        logger.warning("카카오 헬스장 검색 실패(%s) — 등록된 헬스장만 반환", type(exc).__name__)
        return out

    known = await run_in_threadpool(_known_ids, db, [g["id"] for g in found])
    for g in found:
        place_id = known.get(g["id"], g["id"])
        if place_id in seen:
            continue
        seen.add(place_id)
        out.append(TrainerGymCandidate(
            id=place_id, name=g["name"], address=g["address"],
            lat=g["lat"], lng=g["lng"], phone=g["phone"],
            distance_meters=g["distance_meters"],
            registered=g["id"] in known,
        ))
    return out


def _registered_candidates(db: Session, query: str) -> list[TrainerGymCandidate]:
    """등록된 헬스장 후보(전화번호 포함). 동기 DB — 스레드풀에서 부른다."""
    return [
        TrainerGymCandidate(
            id=p.id, name=p.name, address=p.address, lat=p.lat, lng=p.lng,
            phone=_phone_of(db, p.id), registered=True,
        )
        for p in _registered_matches(db, query)
    ]


def _select_existing(
    db: Session, trainer: User, profile: TrainerProfile, kakao_place_id: str
) -> tuple[bool, TrainerMe | None]:
    """이미 `places` 에 있는 곳이면 (True, 결과). 없으면 (False, None). 동기 DB."""
    place = _existing_place(db, kakao_place_id)
    if place is None:
        return False, None
    if place.category != "fitness":
        return True, None
    return True, trainer_gym_service.set_trainer_gym(db, trainer, profile, place.id)


def _phone_of(db: Session, place_id: str) -> str:
    gym = db.get(GymProfile, place_id)
    return gym.phone if gym else ""


def _known_ids(db: Session, kakao_ids: list[str]) -> dict[str, str]:
    """카카오 id → 이미 있는 fitness `places.id`.

    id 가 같으면 그 행이고, 다른 id 로 넣은 행이라도 `kakao_place_id` 가 같으면
    같은 헬스장이다.
    """
    if not kakao_ids:
        return {}
    rows = db.execute(
        select(Place.id, Place.kakao_place_id).where(
            Place.category == "fitness",
            or_(Place.id.in_(kakao_ids), Place.kakao_place_id.in_(kakao_ids)),
        )
    ).all()
    out: dict[str, str] = {}
    for place_id, kakao_id in rows:
        if place_id in kakao_ids:
            out[place_id] = place_id
        if kakao_id and kakao_id in kakao_ids:
            out.setdefault(kakao_id, place_id)
    return out


def _existing_place(db: Session, kakao_place_id: str) -> Place | None:
    return db.scalar(
        select(Place).where(
            or_(Place.id == kakao_place_id, Place.kakao_place_id == kakao_place_id)
        )
    )


async def select_kakao_gym(
    db: Session,
    trainer: User,
    profile: TrainerProfile,
    kakao_place_id: str,
    name: str,
) -> TrainerMe | None:
    """카카오 검색 결과로 소속을 정한다. 헬스장이 아니거나 못 찾으면 None(404).

    1. 이미 `places` 에 있으면 그 행으로 소속만 바꾼다.
    2. 없으면 `name` 으로 카카오를 다시 검색해 id 가 같은 헬스장을 찾는다. 찾은
       값으로 `places`·`gym_profiles` 를 만들고 소속을 설정한다.
    """
    handled, me = await run_in_threadpool(
        _select_existing, db, trainer, profile, kakao_place_id
    )
    if handled:
        return me

    if not kakao_enabled():
        raise GymLookupUnavailable

    settings = get_settings()
    try:
        found = await kakao.search_gyms(
            name, None, None,
            api_key=settings.kakao_rest_api_key,
            timeout=settings.kakao_timeout_seconds,
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning("카카오 헬스장 확인 실패(%s)", type(exc).__name__)
        raise GymLookupUnavailable from exc

    match = next((g for g in found if g["id"] == kakao_place_id), None)
    if match is None:
        return None
    return await run_in_threadpool(_insert_and_select, db, trainer, profile, match)


def _insert_and_select(
    db: Session, trainer: User, profile: TrainerProfile, match: dict
) -> TrainerMe:
    """카카오에서 확인한 헬스장을 `places`·`gym_profiles` 에 넣고 소속을 정한다. 동기 DB."""
    db.add(Place(
        id=match["id"], name=match["name"][:200], category="fitness",
        address=match["address"][:300], lat=match["lat"], lng=match["lng"],
        kakao_place_id=match["id"],
    ))
    try:
        db.flush()
    except IntegrityError:
        # 다른 트레이너가 같은 헬스장을 먼저 넣었다 — 그 행을 쓴다.
        db.rollback()
    else:
        # 영업시간·평점은 카카오가 주지 않는다. 전화만 싣고 제휴는 아니다.
        db.add(GymProfile(
            place_id=match["id"], rating=None, phone=match["phone"][:20],
            is_partner=False,
        ))
        db.flush()
    return trainer_gym_service.set_trainer_gym(db, trainer, profile, match["id"])
