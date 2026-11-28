"""회원용 헬스장 이름 검색. (#3355)

헬스장 찾기의 검색창은 받아 둔 주변 목록을 이름으로 거를 뿐이라, 목록 밖의 헬스장은
이름을 정확히 쳐도 나오지 않았다. 여기서는 등록된 헬스장(`places`)을 이름·주소로
찾고, 트레이너 소속 검색(`trainer_gym_search`)이 쓰는 카카오 이름 검색·헬스장 판별을
그대로 써서 결과를 합친다.

목록(`gym_service.list_gyms`)과 같은 규칙을 따른다 — 데모 시드가 꺼진 서버는 가상
헬스장을 내지 않고, 한 번에 `DEFAULT_GYM_LIMIT` 곳까지만 준다. **반경은 걸지 않는다.**
이름을 알고 찾는 것이라 다른 동네의 헬스장도 나와야 한다.

**카카오에서만 찾은 헬스장은 `places` 에 넣지 않는다.** 트레이너가 소속으로 고른
곳만 `places` 에 들어간다는 규칙(#2543)을 회원의 검색이 깨면 안 된다. 그런 줄의
`id` 는 카카오 장소 id 이고 `/gyms/{id}` 로는 읽히지 않는다 — 주변 검색
(`/places/nearby`)이 준 헬스장과 같은 취급이다.

`async` 안의 DB 작업은 스레드풀로 넘기고(#2835), 카카오를 기다리기 전에 연결을 풀로
돌려준다(#3242) — `trainer_gym_search` 와 같다.
"""
from __future__ import annotations

import logging

from sqlalchemy import and_
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.core.config import get_settings
from app.db.session import release_connection
from app.models.models import Place
from app.schemas.gym_api import GymOut
from app.services import gym_service, trainer_gym_search
from app.services.places import kakao

logger = logging.getLogger(__name__)


def _name_key(name: str) -> str:
    """같은 헬스장인지 견줄 이름 — 띄어쓰기·대소문자를 보지 않는다."""
    return "".join(name.split()).casefold()


def _registered(
    db: Session, query: str, lat: float | None, lng: float | None, limit: int
) -> list[GymOut]:
    """등록된 헬스장 중 검색어의 모든 단어가 이름·주소에 있는 곳. 동기 DB.

    좌표가 없으면 이름순으로 `limit` 곳까지만 읽는다. 좌표가 있으면 가까운 순으로
    잘라야 하므로 맞는 곳을 모두 읽고, 자르는 것은 합친 뒤(`search`)에 한다.
    """
    conditions = trainer_gym_search.match_conditions(query)
    if not conditions:
        return []
    stmt = gym_service._gym_query().where(and_(*conditions)).order_by(Place.name)
    if lat is None or lng is None:
        stmt = stmt.limit(limit)
    return [
        gym_service._to_gym(place, profile, lat, lng)
        for place, profile in db.execute(stmt)
    ]


def _registered_by_ids(
    db: Session, place_ids: list[str], lat: float | None, lng: float | None
) -> dict[str, GymOut]:
    """카카오 결과가 가리키는 등록 헬스장. 데모 제외는 `_gym_query` 가 건다. 동기 DB."""
    if not place_ids:
        return {}
    rows = db.execute(gym_service._gym_query().where(Place.id.in_(place_ids)))
    return {
        place.id: gym_service._to_gym(place, profile, lat, lng)
        for place, profile in rows
    }


def _known(
    db: Session, kakao_ids: list[str], lat: float | None, lng: float | None
) -> tuple[dict[str, str], dict[str, GymOut]]:
    """카카오 id → 등록된 `places.id`, 그리고 그 헬스장들. 동기 DB."""
    known = trainer_gym_search._known_ids(db, kakao_ids)
    gyms = _registered_by_ids(db, sorted(set(known.values())), lat, lng)
    return known, gyms


def _from_kakao(doc: dict, lat: float | None, lng: float | None) -> GymOut:
    """카카오에서만 찾은 헬스장. 평점·태그·영업시간은 카카오가 주지 않아 비운다."""
    distance_km = 0.0
    if lat is not None and lng is not None:
        # 등록 헬스장과 같은 계산으로 잰다 — 두 출처의 거리가 한 목록에 섞인다.
        distance_km = gym_service._haversine_m(lat, lng, doc["lat"], doc["lng"]) / 1000
    return GymOut(
        id=doc["id"],
        name=doc["name"],
        address=doc["address"],
        distance_km=distance_km,
        rating=0.0,
        tags=[],
        weekday_hours=None,
        weekend_hours=None,
        phone=doc["phone"] or None,
        lat=doc["lat"],
        lng=doc["lng"],
        is_partner=False,
    )


async def _external(
    db: Session, query: str, lat: float | None, lng: float | None
) -> list[GymOut]:
    """카카오 이름 검색 결과. 쓸 수 없거나 실패하면 빈 목록 — 검색은 등록 헬스장으로 답한다."""
    if not trainer_gym_search.kakao_enabled():
        return []
    settings = get_settings()
    await run_in_threadpool(release_connection, db)
    try:
        found = await kakao.search_gyms(
            query, lat, lng,
            api_key=settings.kakao_rest_api_key,
            timeout=settings.kakao_timeout_seconds,
        )
    except Exception as exc:  # noqa: BLE001 — 외부 API 실패가 검색을 깨지 않도록
        # 예외 repr 에 좌표가 든 요청 URL 이 들어갈 수 있어 타입만 남긴다.
        logger.warning("카카오 헬스장 검색 실패(%s) — 등록된 헬스장만 반환", type(exc).__name__)
        return []

    known, registered = await run_in_threadpool(
        _known, db, [g["id"] for g in found], lat, lng
    )
    out: list[GymOut] = []
    for doc in found:
        place_id = known.get(doc["id"])
        if place_id is None:
            out.append(_from_kakao(doc, lat, lng))
        elif place_id in registered:
            # 이미 등록된 곳이면 정보가 더 많은 등록 쪽을 싣는다.
            out.append(registered[place_id])
        # 등록됐지만 디렉터리에 내지 않는 곳(데모 제외)은 카카오 쪽으로도 싣지 않는다.
    return out


async def search(
    db: Session,
    query: str,
    lat: float | None = None,
    lng: float | None = None,
    *,
    limit: int = gym_service.DEFAULT_GYM_LIMIT,
) -> list[GymOut]:
    """이름으로 찾은 헬스장 — 등록된 곳과 카카오 결과를 합쳐 `limit` 곳까지.

    같은 헬스장은 한 번만 싣는다. id 가 같거나(카카오 id 로 등록된 곳), 이름이
    같으면(시드 제휴 헬스장은 id 가 카카오와 다르다) 같은 곳으로 본다.

    좌표가 있으면 가까운 순, 없으면 등록된 헬스장(이름순)을 먼저 두고 카카오 결과를
    카카오가 준 순서로 잇는다. 좌표를 모르는 헬스장은 거리순의 맨 뒤다.
    """
    merged = await run_in_threadpool(_registered, db, query, lat, lng, limit)
    seen_ids = {g.id for g in merged}
    seen_names = {_name_key(g.name) for g in merged}
    for gym in await _external(db, query, lat, lng):
        key = _name_key(gym.name)
        if gym.id in seen_ids or key in seen_names:
            continue
        seen_ids.add(gym.id)
        seen_names.add(key)
        merged.append(gym)

    if lat is not None and lng is not None:
        merged.sort(
            key=lambda g: (g.lat is None or g.lng is None, g.distance_km, g.name)
        )
    return merged[:limit]
