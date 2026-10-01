"""
장소 라우터 (온오프라인 연결) — 프론트 계약 정렬.

  GET /places/nearby?lat=&lng=&category=  -> 주변 장소 배열(거리순)

현재는 DB 에 시드된 장소를 거리 계산해 반환합니다.
카카오맵 실연동(developers.kakao.com 키 필요)은 _search_kakao() 자리에 채웁니다.
연동 후에도 응답 형식(PlaceOut)은 동일하므로 프론트는 영향 없음.
"""
from __future__ import annotations

import logging
import math
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.api.deps import CurrentUser
from app.core.config import get_settings
from app.db.session import get_db
from app.models.models import Place
from app.schemas.misc_api import PlaceOut
from app.services.places import kakao

router = APIRouter(tags=["places"])
logger = logging.getLogger(__name__)


def _use_kakao(settings) -> bool:
    """카카오 실검색을 쓸지: provider=kakao 강제거나, auto+키 보유."""
    provider = settings.places_provider
    if provider == "seed":
        return False
    if provider == "kakao":
        return True
    return bool(settings.kakao_rest_api_key)  # auto


def _haversine_m(lat1, lng1, lat2, lng2) -> int:
    """두 좌표 간 거리(m)."""
    r = 6371000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return int(r * 2 * math.asin(math.sqrt(a)))


@router.get("/places/nearby", response_model=list[PlaceOut])
async def places_nearby(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    lat: float = Query(37.5665, ge=-90, le=90, description="기준 위도(기본: 서울시청)"),
    lng: float = Query(126.9780, ge=-180, le=180, description="기준 경도"),
    category: Literal["medical", "fitness", "healthy_food", "pharmacy"] | None = Query(
        None, description="medical|fitness|healthy_food|pharmacy"
    ),
    radius_m: int = Query(3000, ge=100, le=20000),
) -> list[PlaceOut]:
    """주변 장소(거리순). 카카오 키가 있으면 실검색, 없거나 실패하면 시드 폴백.
    응답 형식(PlaceOut)은 두 경로 동일하므로 프론트는 영향 없음."""
    settings = get_settings()
    if _use_kakao(settings) and settings.kakao_rest_api_key:
        try:
            places = await kakao.search_nearby(
                lat, lng, category, radius_m,
                api_key=settings.kakao_rest_api_key,
                timeout=settings.kakao_timeout_seconds,
            )
            if places:
                return places
            # 결과 0건이면 시드로 폴백(데모가 비지 않도록)
        except Exception as exc:  # noqa: BLE001 — 외부 API 실패가 요청을 깨지 않도록 폴백
            # httpx 예외 repr에는 사용자 좌표(x/y)가 포함된 요청 URL이 들어갈 수 있다.
            logger.warning(
                "카카오 장소검색 실패(%s) — 시드 데이터로 폴백",
                type(exc).__name__,
            )
    # 시드 조회는 동기 DB 다 — 이벤트 루프를 막지 않게 스레드풀로 넘긴다(#2835).
    return await run_in_threadpool(_seed_nearby, db, lat, lng, category, radius_m)


def _seed_nearby(
    db: Session, lat: float, lng: float, category: str | None, radius_m: int
) -> list[PlaceOut]:
    """DB 시드 장소를 거리 계산해 반환(카카오 미연동/실패 시 폴백)."""
    q = select(Place)
    if category:
        q = q.where(Place.category == category)
    rows = db.scalars(q).all()

    out: list[PlaceOut] = []
    for r in rows:
        if r.lat is None or r.lng is None:
            continue
        dist = _haversine_m(lat, lng, r.lat, r.lng)
        if dist > radius_m:
            continue
        out.append(PlaceOut(
            id=r.id, name=r.name, category=r.category, address=r.address,
            distance_meters=dist, lat=r.lat, lng=r.lng,
        ))
    out.sort(key=lambda p: p.distance_meters)
    return out
