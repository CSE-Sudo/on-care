"""
식단 라우터 — 프론트 계약 정렬(얇은 라우터).

  GET  /diet/days/today          -> 오늘 식단 집계(나트륨·당류·macros + 코칭 메시지)
  GET  /diet/days/{date}         -> 지정 날짜 식단 집계
  GET  /diet/recommendations     -> 홈 AI 추천 식단(카탈로그에서 개인화 선택)
  POST /diet/analyze             -> 사진 → 인식 → diet_entries 저장(+ 사진 축소본, 포인트 적립)
  POST /diet/analyze?engine=yolo -> 엔진 강제(비교실험)
  GET  /diet/photos/{photo_id}   -> 내 끼니 사진 원본 바이트(본인만)
  PUT/DELETE /diet/entries/{id}  -> 끼니/영양소 수정·삭제(본인 소유만, 삭제는 적립 회수)

집계·코칭·저장 등 도메인 로직은 diet_service 로 이관했다(exercise_service 등과 일관).
라우터는 HTTP 관심사(업로드 검증·인식기 디스패치·에러 매핑)만 담당한다.
"""
from __future__ import annotations

import logging
from datetime import date as Date
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Response, UploadFile
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser
from app.core.config import get_settings
from app.db.session import get_db
from app.schemas.diet_api import (
    DietAdviceResponse,
    DietAnalyzeResponse,
    DietEntryOut,
    DietEntryUpdate,
    DietRecommendationsResponse,
    DietTodayResponse,
)
from app.schemas.points_api import PointsOut
from app.services import (
    diet_photo_service,
    diet_recommendation_service,
    diet_service,
    points_service,
)
from app.services.coach import personal_ingest
from app.services.nutrition.enrich import enrich_analysis
from app.services.recognizer.factory import get_recognizer

router = APIRouter(tags=["diet"])
logger = logging.getLogger(__name__)

_ALLOWED_MIME = {"image/jpeg", "image/png", "image/webp"}


@router.get("/diet/days/today", response_model=DietTodayResponse)
def diet_today(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> DietTodayResponse:
    return diet_service.build_today(db, current_user.id)


@router.get("/diet/days/{date}", response_model=DietTodayResponse)
def diet_by_date(
    date: Date,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> DietTodayResponse:
    return diet_service.build_day(db, current_user.id, date.isoformat())


@router.get("/diet/advice", response_model=DietAdviceResponse)
def diet_advice(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    period: Annotated[
        Literal["today", "week", "all"],
        Query(description="조언이 다룰 구간 — 화면의 기간 토글과 같은 이름"),
    ] = "today",
) -> DietAdviceResponse:
    """기간에 맞는 식단 조언. (#1017)

    기간을 바꾸는 것은 "무엇을 볼지" 를 바꾸는 일이다. 그래프만 갈아 끼우고
    조언이 오늘 이야기로 남으면 지금 화면과 무관한 말이 된다.

    경계는 서버가 정한다 — 앱과 트레이너웹이 각자 계산하면 같은 회원의 `이번 주`
    가 화면마다 다른 날부터 시작한다.
    """
    return _advice_for(db, current_user.id, period)


def _advice_for(db: Session, user_id: str, period: str) -> DietAdviceResponse:
    start, end = diet_service.period_bounds(period)
    days = diet_service.daily_totals(db, user_id, start, end)
    return DietAdviceResponse(
        period=period,
        from_date=start,
        to_date=end,
        days_logged=len(days),
        message=diet_service.period_coach_message(days, period),
    )


@router.get("/diet/recommendations", response_model=DietRecommendationsResponse)
def diet_recommendations(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    use_llm: Annotated[
        bool,
        Query(description="false 면 LLM 을 건너뛰고 규칙 추천만 쓴다(테스트·비용 절감용)"),
    ] = True,
) -> DietRecommendationsResponse:
    """홈 'AI 추천 식단' — 카탈로그에서 개인화 선택.

    LLM 실패·지연·근거 부족 어느 경우에도 카드 수가 줄지 않는다(서비스 주석 참고).
    """
    return diet_recommendation_service.build_recommendations(
        db, current_user.id, use_llm=use_llm
    )


@router.post("/diet/analyze", response_model=DietAnalyzeResponse)
async def diet_analyze(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    image: UploadFile = File(..., description="음식 사진"),
    meal_type: str = Form("lunch", description="breakfast|lunch|dinner|snack"),
    idempotency_key: str | None = Form(
        None,
        max_length=64,  # DietEntry.idempotency_key 컬럼(String(64)) 경계와 일치 — 초과 시 DB 500 방지
        description="재시도 중복 저장 방지 키(선택). 클라 요청당 1회 생성해 재시도 시 재사용.",
    ),
    engine: str | None = Query(None, description="엔진 강제('gemini'|'yolo'). 비교실험용."),
) -> DietAnalyzeResponse:
    if image.content_type not in _ALLOWED_MIME:
        raise HTTPException(status_code=415, detail=f"지원하지 않는 형식: {image.content_type}")
    image_bytes = await image.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="빈 파일입니다.")

    # 멱등키가 있고 이미 저장된 요청이면 인식·저장을 건너뛰고 기존 결과 반환(재시도 중복 방지)
    if idempotency_key:
        existing = diet_service.find_by_idempotency(db, current_user.id, idempotency_key)
        if existing is not None:
            return DietAnalyzeResponse(
                entry_id=existing.id,
                analysis=diet_service.entry_to_analysis(existing),
                points=_points_already_awarded(db, current_user.id, existing.id),
            )

    try:
        recognizer = get_recognizer(engine)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    try:
        analysis = await recognizer.recognize(image_bytes, image.content_type)
    except NotImplementedError as e:
        raise HTTPException(status_code=501, detail=str(e)) from e
    except Exception as e:  # noqa: BLE001
        # 원본 에러(API 키/내부 URL 등)는 서버 로그에만 남기고, 클라이언트엔 일반화된 메시지
        logger.exception("식단 인식 실패 (engine=%s)", engine)
        raise HTTPException(
            status_code=502, detail="식단 인식에 실패했습니다. 잠시 후 다시 시도해 주세요."
        ) from e

    # 공공 식품영양성분 DB 매핑으로 영양 수치 보강(매칭 시 신뢰값으로 교체 → 합계 재계산)
    enrich_analysis(db, analysis, enabled=get_settings().nutrition_db_enrich)

    entry, is_new = diet_service.save_analyzed_entry(
        db, current_user.id, meal_type, analysis, idempotency_key
    )
    entry_id = entry.id
    if not is_new:
        # 동시 재시도가 유니크 제약에 걸려 기존 엔트리를 받은 경우(중복 저장 방지)
        return DietAnalyzeResponse(
            entry_id=entry_id,
            analysis=diet_service.entry_to_analysis(entry),
            points=_points_already_awarded(db, current_user.id, entry_id),
        )

    points = _award_points(db, current_user.id, entry_id)

    # 인식이 끝난 사진을 끼니에 붙인다. 실패해도 끼니 기록은 그대로 남는다(#699).
    photo = diet_photo_service.store_for_entry(db, current_user.id, entry_id, image_bytes)

    # 모델 원본 출력(raw_model_output)은 클라이언트로 내보내지 않음(디버깅 전용)
    analysis.raw_model_output = None
    return DietAnalyzeResponse(
        entry_id=entry_id,
        analysis=analysis,
        photo_url=diet_service.member_photo_url(photo.id) if photo else None,
        points=points,
    )


def _award_points(db: Session, user_id: str, entry_id: str) -> PointsOut:
    """새 끼니의 포인트 적립(#1786). 저장이 끝난 바로 뒤에 따로 커밋한다.

    저장(`save_analyzed_entry`)은 멱등키 충돌을 제 커밋 안에서 처리하므로 그 사이에
    끼워 넣지 않는다. 적립이 실패해도 끼니 기록은 남는다 — 사진과 같은 규칙이다(#699).
    그때 응답은 적립 0 이라 앱은 적립 표시 없이 저장 알림만 띄운다.
    """
    try:
        result = points_service.award(
            db, user_id, points_service.DIET_ENTRY, entry_id
        )
        db.commit()
    except SQLAlchemyError:
        db.rollback()
        logger.exception("식단 포인트 적립 실패 — 끼니 기록은 유지")
        return PointsOut(awarded=0, balance=points_service.balance(db, user_id))
    return PointsOut.of(result)


def _points_already_awarded(db: Session, user_id: str, entry_id: str) -> PointsOut:
    """재시도로 되돌아온 끼니가 처음 저장될 때 받은 적립. 새로 적립하지 않는다."""
    return PointsOut.of(
        points_service.awarded_for(db, user_id, points_service.DIET_ENTRY, entry_id)
    )


@router.get("/diet/photos/{photo_id}")
def diet_photo(
    photo_id: str,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> Response:
    """내 끼니 사진. 남의 사진은 404 — 주소를 추측해도 열리지 않는다. (#699)

    담당 트레이너는 이 경로가 아니라 `/trainer/clients/{id}/diet/photos/{photo_id}`
    로 본다(회원 API 와 트레이너 API 의 역할 분리).
    """
    photo = diet_photo_service.get_owned_photo(db, photo_id, current_user.id)
    if photo is None:
        raise HTTPException(status_code=404, detail="사진을 찾을 수 없습니다.")
    return Response(
        content=photo.data,
        media_type=photo.content_type,
        # 사적인 이미지다 — 공유 캐시(프록시·CDN)에 남으면 안 된다. 사진 내용은
        # 바뀌지 않으므로(끼니 하나에 사진 하나) 브라우저 캐시는 길게 허용한다.
        headers={"Cache-Control": "private, max-age=86400"},
    )


@router.put("/diet/entries/{entry_id}", response_model=DietEntryOut)
def update_entry(
    entry_id: str,
    payload: DietEntryUpdate,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> DietEntryOut:
    """식단 기록의 끼니 분류/시간·영양소 수정(본인 소유만, 아니면 404)."""
    row = diet_service.get_owned_entry(db, current_user.id, entry_id)
    if row is None:
        raise HTTPException(status_code=404, detail="식단 기록을 찾을 수 없습니다.")
    return diet_service.apply_entry_update(db, row, payload)


@router.delete("/diet/entries/{entry_id}")
def delete_entry(
    entry_id: str,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """식단 기록 삭제. 본인 소유 엔트리만 삭제 가능(아니면 404)."""
    row = diet_service.get_owned_entry(db, current_user.id, entry_id)
    if row is None:
        raise HTTPException(status_code=404, detail="식단 기록을 찾을 수 없습니다.")
    # 이 끼니로 받은 포인트를 회수한다. 기록 삭제와 같은 트랜잭션이라 기록만
    # 사라지고 포인트가 남는 일이 없다(#1786).
    points_service.revoke(
        db, current_user.id, points_service.SOURCE_DIET_ENTRY, row.id
    )
    db.delete(row)
    db.commit()
    # 근거 문서도 지운다(#603). 남겨 두면 코치가 사용자가 지운 기록으로 계속
    # 조언해, 지운 것이 되살아나는 것처럼 보인다.
    personal_ingest.forget(db, current_user.id, entry_id)
    return {"status": "deleted"}
