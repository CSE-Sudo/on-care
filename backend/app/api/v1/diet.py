"""
식단 라우터 — 프론트 계약 정렬(얇은 라우터).

  GET  /diet/days/today          -> 오늘 식단 집계(나트륨·당류·macros + 코칭 메시지)
  GET  /diet/days?from=&to=      -> 기간의 날짜별 합계(그래프용, 끼니·사진 없음)
  GET  /diet/days/{date}         -> 지정 날짜 식단 집계
  GET  /diet/recommendations     -> 홈 AI 추천 식단(카탈로그에서 개인화 선택)
  POST /diet/analyze             -> 사진 정리(EXIF 제거) → 인식 → diet_entries 저장(+ 사진 축소본, 포인트 적립)
  POST /diet/analyze?engine=gemini -> 엔진 강제(비교실험 — 운영에서는 관리자만, #2812)
  GET  /diet/photos/{photo_id}   -> 내 끼니 사진 원본 바이트(본인만)
  POST /diet/entries             -> 사진 없이 직접 적은 끼니 저장(포인트 없음)
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
from starlette.concurrency import run_in_threadpool

from app.api import ai_call_errors
from app.api.deps import CurrentUser, RequireMember
from app.core import rate_limit
from app.core.config import get_settings
from app.db.session import get_db
from app.schemas.diet import DietAnalysis
from app.schemas.diet_api import (
    DietAdviceResponse,
    DietAnalyzeResponse,
    DietEntryCreate,
    DietEntryOut,
    DietEntryUpdate,
    DietPeriodResponse,
    DietRecommendationsResponse,
    DietTodayResponse,
    FoodNutritionOut,
    FoodNutritionRequest,
    MealTypeLiteral,
    MemberTrainerPick,
    analyze_record_date,
)
from app.schemas.points_api import PointsOut
from app.services.ai_log import log_ai_fallback
from app.services import (
    ai_call_quota,
    chat_image_storage,
    diet_advice_copy,
    diet_all_advice,
    diet_analysis_quota_service,
    diet_period_advice,
    diet_photo_service,
    diet_recommendation_service,
    diet_service,
    diet_trainer_pick,
    diet_week_advice,
    image_sanitize,
    points_service,
)
from app.services.coach import personal_ingest
from app.services.nutrition.enrich import enrich_analysis, lookup_by_name
from app.services.recognizer.factory import (
    STUB_ENGINE,
    RecognizerUnavailable,
    get_recognizer,
)

router = APIRouter(tags=["diet"])

logger = logging.getLogger(__name__)

#: 사진 분석 분당 한도 초과(#2827). 하루 상한(`daily_limit`)과 달리 잠시 뒤 다시 된다.
_RATE_LIMITED = {
    "code": "rate_limited",
    "message": "사진 분석 요청이 너무 잦아요. 잠시 후 다시 시도해 주세요.",
}

#: 사진 분석을 쓸 수 없는 설정(운영에서 키 없음)일 때의 503 본문(#2812). 앱은 `code` 로
#: 일반 실패와 구분해 직접 입력으로 이어 준다.
_ANALYSIS_UNAVAILABLE = {
    "code": "analysis_unavailable",
    "message": "사진 분석을 잠시 쓸 수 없어요. 직접 추가로 기록할 수 있어요.",
}

#: 사진에서 음식을 하나도 찾지 못했을 때의 422 본문(#2848). 끼니·포인트·사진을 남기지
#: 않고 멱등키도 쓰지 않는다 — 앱은 다른 사진 고르기·직접 입력으로 이어 준다.
_NO_FOOD_DETECTED = {
    "code": "no_food_detected",
    "message": "사진에서 음식을 찾지 못했어요. 다른 사진을 고르거나 직접 추가해 주세요.",
}

#: 형식은 맞지만 픽셀을 읽을 수 없는 사진의 415 본문(#3041). 형식 판정 415 와 같은
#: 문자열 모양이라 앱은 같은 "지원하지 않는 사진" 안내를 띄운다.
_UNREADABLE_IMAGE = "이미지를 읽을 수 없어요. 다른 사진을 골라 주세요."


@router.get("/diet/days/today", response_model=DietTodayResponse)
def diet_today(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> DietTodayResponse:
    return diet_service.build_today(db, current_user.id)


@router.get("/diet/days", response_model=DietPeriodResponse)
def diet_period(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    from_date: Annotated[Date | None, Query(alias="from")] = None,
    to_date: Annotated[Date | None, Query(alias="to")] = None,
) -> DietPeriodResponse:
    """기간의 **날짜별 합계**. `from` 을 생략하면 첫 기록일부터다. (#2236)

    기간 그래프가 쓰는 길이다 — 하루에 한 번씩 부르면 `전체`(모든 기록, #2079)가
    수백 번의 왕복이 된다. 끼니·사진은 싣지 않으므로 하루를 펼쳐 볼 때는 그대로
    `GET /diet/days/{date}` 를 쓴다.

    구간은 끝에서 거슬러 최대 `MAX_PERIOD_DAYS`(1100일)다. 더 이른 `from`·첫 기록일은
    그 하한으로 잘리고, 응답 `from_date` 가 실제 시작일이다(#2833).
    """
    return diet_service.build_period(db, current_user.id, start=from_date, end=to_date)


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
    lang: Annotated[
        Literal["ko", "en"],
        Query(description="앱 언어 — 메뉴 이름·AI 문장을 이 언어로 준다"),
    ] = "ko",
) -> DietAdviceResponse:
    """기간에 맞는 식단 조언. (#1017)

    기간을 바꾸는 것은 "무엇을 볼지" 를 바꾸는 일이다. 그래프만 갈아 끼우고
    조언이 오늘 이야기로 남으면 지금 화면과 무관한 말이 된다.

    경계는 서버가 정한다 — 앱과 트레이너웹이 각자 계산하면 같은 회원의 `이번 주`
    가 화면마다 다른 날부터 시작한다.

    조언은 규칙 한 줄 + 다음 할 일 한 문장이다(#2251). `오늘` 은 4주 추천 메뉴
    리스트에서 다음 식사를 고르고, `이번 주` 는 규칙이 고른 한 가지에 AI 가 원인
    메뉴나 대안을 붙인다(하루 한 번, #2253). `전체` 는 최근 4주 식습관 하나에 AI 가
    다음 4주의 행동 목표를 붙인다(주 한 번, #2254). 트레이너웹 경로는
    `diet_trainer_analysis` 의 식단 분석 문장이다(#2379).
    """
    if period == diet_period_advice.PERIOD_TODAY:
        return _advice_response(
            diet_period_advice.today_advice(db, current_user.id, lang=lang)
        )
    if period == diet_week_advice.PERIOD_WEEK:
        return _advice_response(
            diet_week_advice.week_advice(db, current_user.id, lang=lang)
        )
    return _advice_response(diet_all_advice.all_advice(db, current_user.id, lang=lang))


def _advice_response(advice: diet_period_advice.DietAdvice) -> DietAdviceResponse:
    action = advice.action
    return DietAdviceResponse(
        period=advice.period,
        from_date=advice.from_date,
        to_date=advice.to_date,
        days_logged=advice.days_logged,
        message=diet_advice_copy.message(advice.analysis, action),
        analysis=advice.analysis.text,
        analysis_key=advice.analysis.key,
        analysis_params=advice.analysis.params,
        action=action.text if action else "",
        action_key=action.key if action else None,
        action_params=action.params if action else {},
        action_source=advice.action_source,
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
    response = diet_recommendation_service.build_recommendations(
        db, current_user.id, use_llm=use_llm
    )
    # 트레이너가 확정한 추천(#2378)은 캐시 밖에서 붙인다 — 회원이 방금 그 메뉴를
    # 먹었거나 트레이너가 방금 바꿨는데 캐시가 옛 추천을 들고 있으면 안 된다.
    found = diet_trainer_pick.for_member(db, current_user.id)
    if found is None:
        return response
    pick, trainer_name = found
    return response.model_copy(
        update={
            "trainer_pick": MemberTrainerPick(
                slot=pick.slot, name=pick.name, tag=pick.tag,
                keyword=pick.keyword, trainer_name=trainer_name,
            )
        }
    )


@router.post("/diet/nutrition", response_model=FoodNutritionOut)
def food_nutrition(
    payload: FoodNutritionRequest,
    current_user: RequireMember,  # noqa: ARG001 — 로그인한 회원만 쓰는 조회다
    db: Annotated[Session, Depends(get_db)],
) -> FoodNutritionOut:
    """음식 이름으로 공공 영양 DB 값을 찾는다. (#1896)

    수정 화면이 이름을 고쳤을 때 "이 이름이면 값이 이렇다" 를 **제안**하는 데
    쓴다. 덮어쓰기는 앱이 하지 않는다 — 이름 변경은 "다른 음식이다" 일 수도
    "오타를 고쳤다" 일 수도 있어 서버가 구분할 수 없고, 자동으로 갈아 끼우면
    회원이 손으로 바로잡아 둔 값이 소리 없이 사라진다.

    계산은 분석 보정(`enrich_analysis`)과 **같은 것**이다. 음식 하나짜리 보정과
    같은 일이라, 따로 두면 같은 음식인데 화면 어디서 왔느냐에 따라 숫자가 갈린다.

    이름이 비어 있으면 400 — 이름 없이 확정된 숫자를 내주지 않는 것이 이 조회의
    요점이다(`POST /exercise/calories` 와 같은 규약, #1312). 못 찾았거나 양을
    정할 수 없으면 `matched_name` 이 null 이고, 그때 앱은 아무것도 제안하지 않는다.
    """
    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="음식 이름을 입력해 주세요.")
    found = lookup_by_name(db, name, payload.amount_g)
    if found is None:
        return FoodNutritionOut()
    match, food, exact = found
    return FoodNutritionOut(
        matched_name=match.name,
        match="exact" if exact else "similar",
        source=food.source,
        amount_g=food.amount_g,
        calories=food.calories,
        carbs_g=food.carbs_g,
        protein_g=food.protein_g,
        fat_g=food.fat_g,
        sodium_mg=food.sodium_mg,
        sugar_g=food.sugar_g,
    )


def _analyze_record_date(
    record_date: str | None = Form(
        None,
        alias="date",
        description="기록 날짜(YYYY-MM-DD, 선택). 빠지면 저장하는 날. 앞날·작년 1월 1일 이전은 422.",
    ),
) -> Date | None:
    """사진 분석의 기록 날짜(#2849). 지난 날짜 화면에서 연 추가는 그 날로 남긴다.

    의존성으로 두어 본문보다 먼저 돈다 — 인식(비용이 드는 외부 호출) 전에 걸러 낸다.
    """
    try:
        return analyze_record_date(record_date)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e)) from e


@router.post("/diet/analyze", response_model=DietAnalyzeResponse)
async def diet_analyze(
    current_user: RequireMember,
    db: Annotated[Session, Depends(get_db)],
    image: UploadFile = File(..., description="음식 사진"),
    # 다섯 값 밖은 인식 전에 422 다(#2882) — 직접 기록·수정과 같은 규칙.
    meal_type: MealTypeLiteral = Form("lunch", description="breakfast|lunch|dinner|snack|lateNight"),
    entry_date: Date | None = Depends(_analyze_record_date),
    idempotency_key: str | None = Form(
        None,
        max_length=64,  # DietEntry.idempotency_key 컬럼(String(64)) 경계와 일치 — 초과 시 DB 500 방지
        description="재시도 중복 저장 방지 키(선택). 클라 요청당 1회 생성해 재시도 시 재사용.",
    ),
    engine: str | None = Query(
        None,
        description="엔진 강제('gemini'|'litellm'). 비교실험용 — 운영에서는 관리자만 적용된다.",
    ),
) -> DietAnalyzeResponse:
    image_bytes = await image.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="빈 파일이에요.")
    # 형식은 바이트로 판정한다 — 요청 헤더의 Content-Type 은 보내는 쪽이 적어 준 값일
    # 뿐이라, 이미지가 아닌 본문이 그 말만 믿고 외부 모델 호출까지 가면 안 된다(#2827).
    try:
        chat_image_storage.sniff(image_bytes)
    except chat_image_storage.UnsupportedImage as e:
        raise HTTPException(status_code=415, detail=str(e)) from e

    # 여기부터 DB 작업은 모두 스레드풀에서 한다(#2835). 이 라우트는 업로드를 읽고
    # 외부 모델을 기다리느라 `async def` 지만, 동기 세션 조회·커밋과 Pillow 재인코딩을
    # 이벤트 루프에서 돌리면 그동안 같은 프로세스의 다른 요청(헬스체크 포함)이 모두
    # 멈춘다. 세션은 한 번에 한 스레드만 쓴다(각 단계가 끝나야 다음 단계가 시작된다).
    user_id = current_user.id
    is_admin = current_user.is_admin

    # 멱등키가 있고 이미 저장된 요청이면 인식·저장을 건너뛰고 기존 결과 반환(재시도 중복 방지)
    if idempotency_key:
        replay = await run_in_threadpool(_replay_if_saved, db, user_id, idempotency_key)
        if replay is not None:
            return replay

    # `engine` 은 비교실험용이다. 운영에서 회원이 `?engine=stub` 으로 고정 식단을
    # 저장하거나 준비되지 않은 엔진으로 500 을 내지 못하게, 관리자가 아니면 무시하고
    # 설정된 인식기를 쓴다(#2812).
    if engine is not None and get_settings().is_prod and not is_admin:
        engine = None
    try:
        recognizer = get_recognizer(engine)
    except RecognizerUnavailable as e:
        # 운영인데 인식 키가 없다 — 고정 식단으로 저장하는 대신 분석 불가로 답한다.
        # 끼니·포인트·사진은 남기지 않는다(#2812).
        logger.error("식단 인식기를 쓸 수 없음: %s", e)
        raise HTTPException(status_code=503, detail=_ANALYSIS_UNAVAILABLE) from e
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    # 외부 모델에 보내기 전에 사진을 정리한다(#3041). 휴대폰 사진의 EXIF 에는 촬영
    # 위치·시각·기기가 들어 있어, 원본을 그대로 보내면 집 좌표가 인식 업체로 나간다.
    # 저장도 같은 정리본에서 만든다 — 원본 바이트는 이 지점 뒤로 쓰지 않는다.
    # 읽을 수 없는 사진은 하루 분석 한도를 예약하기 전에 415 로 끝낸다.
    try:
        clean = await run_in_threadpool(
            image_sanitize.to_jpeg,
            image_bytes,
            max_edge=image_sanitize.RECOGNITION_MAX_EDGE,
            quality=image_sanitize.RECOGNITION_JPEG_QUALITY,
        )
    except image_sanitize.UndecodableImage as e:
        raise HTTPException(status_code=415, detail=_UNREADABLE_IMAGE) from e
    del image_bytes

    usage_id = await run_in_threadpool(_reserve_analysis, db, user_id)

    try:
        analysis = await recognizer.recognize(clean.data, clean.media_type)
    except NotImplementedError as e:
        await run_in_threadpool(diet_analysis_quota_service.release, db, usage_id)
        raise HTTPException(status_code=501, detail=str(e)) from e
    except ai_call_quota.AiCapacityReached as e:
        # 서버 전체 하루 AI 상한(#3032). 모델을 부르지 않았으니 회원의 하루 몫을 돌려주고,
        # 앱이 `analysis_unavailable` 처럼 직접 입력으로 이어 주게 503 `ai_capacity` 로 답한다.
        await run_in_threadpool(diet_analysis_quota_service.release, db, usage_id)
        raise ai_call_errors.capacity_http_error(e) from e
    except Exception as e:  # noqa: BLE001
        # 공급자 장애로 회원의 하루 몫이 깎이지 않게 돌려준다.
        await run_in_threadpool(diet_analysis_quota_service.release, db, usage_id)
        # 클라이언트엔 일반화된 메시지. 서버 로그에도 예외 메시지·스택은 남기지 않는다 —
        # provider 오류는 요청 본문을, 검증 오류는 모델 출력을 되풀이한다(#3090).
        log_ai_fallback(
            logger, "diet_recognize", "error", exc=e, level=logging.ERROR,
            engine=engine or "-", user_id=user_id,
        )
        raise HTTPException(
            status_code=502, detail="식단을 인식하지 못했어요. 잠시 후 다시 시도해 주세요."
        ) from e

    # 음식을 하나도 찾지 못한 사진(풍경·사람·빈 그릇)은 끼니가 아니다. 0kcal 끼니를
    # 저장하고 포인트를 주면 아무 사진으로나 적립할 수 있고, 트레이너는 굶은 날과
    # 구분하지 못한다 — 저장·적립·사진 저장 전에 거절한다(#2848).
    if not analysis.foods:
        raise HTTPException(status_code=422, detail=_NO_FOOD_DETECTED)

    return await run_in_threadpool(
        _persist_analysis, db, user_id, meal_type, analysis, idempotency_key, clean.data,
        entry_date,
    )


def _replay_if_saved(db: Session, user_id: str, idempotency_key: str) -> DietAnalyzeResponse | None:
    """같은 멱등키로 이미 저장된 끼니가 있으면 그 응답. 동기 DB(스레드풀에서 부른다)."""
    existing = diet_service.find_by_idempotency(db, user_id, idempotency_key)
    if existing is None:
        return None
    return DietAnalyzeResponse(
        entry_id=existing.id,
        analysis=diet_service.entry_to_analysis(existing),
        time_label=existing.time_label,
        points=_points_already_awarded(db, user_id, existing.id),
    )


def _reserve_analysis(db: Session, user_id: str) -> str | None:
    """모델 호출 한 번을 한도에서 잡는다(#2827). 동기 DB(스레드풀에서 부른다).

    사진 한 장이 외부 비전 모델 호출 한 번이라 비용이 가장 큰 축이다. 멱등 재전송은
    앞에서 모델 없이 돌아갔으므로 여기 오지 않아 세지 않는다. 분당 한도는 사람
    단위(같은 헬스장 Wi-Fi 회원끼리 나눠 쓰지 않게), 하루 상한은 DB 에서 KST 날짜로
    센다.
    """
    rate_limit.check_user(
        "diet-analyze", user_id, get_settings().diet_analyze_per_minute, detail=_RATE_LIMITED
    )
    try:
        return diet_analysis_quota_service.reserve(db, user_id)
    except diet_analysis_quota_service.DailyAnalysisLimitReached as e:
        raise HTTPException(
            status_code=429, detail={"code": "daily_limit", "message": str(e)}
        ) from e


def _persist_analysis(
    db: Session,
    user_id: str,
    meal_type: str,
    analysis: DietAnalysis,
    idempotency_key: str | None,
    image_bytes: bytes,
    entry_date: Date | None = None,
) -> DietAnalyzeResponse:
    """인식 결과를 보강·저장하고 적립·사진 저장까지 한다. 동기(스레드풀에서 부른다).

    DB 왕복(영양 DB 매칭·저장·적립)과 사진 축소(Pillow 재인코딩)가 모두 여기 있다.
    """
    # 공공 식품영양성분 DB 매핑으로 영양 수치 보강(매칭 시 신뢰값으로 교체 → 합계 재계산)
    enrich_analysis(db, analysis, enabled=get_settings().nutrition_db_enrich)

    entry, is_new = diet_service.save_analyzed_entry(
        db, user_id, meal_type, analysis, idempotency_key,
        record_date=entry_date,
    )
    entry_id = entry.id
    # 아래에서 적립·사진 저장이 각각 커밋하므로 그때 이 인스턴스의 속성이
    # 만료된다. 응답에 실을 값은 여기서 함께 잡아 둔다(`entry_id` 와 같은 이유).
    entry_time_label = entry.time_label
    if not is_new:
        # 동시 재시도가 유니크 제약에 걸려 기존 엔트리를 받은 경우(중복 저장 방지)
        return DietAnalyzeResponse(
            entry_id=entry_id,
            analysis=diet_service.entry_to_analysis(entry),
            time_label=entry_time_label,
            points=_points_already_awarded(db, user_id, entry_id),
        )

    # 개발용 고정 식단(스텁)은 사진을 보지 않은 결과다 — 포인트를 주지 않는다(#2812).
    if analysis.engine == STUB_ENGINE:
        points = PointsOut(awarded=0, balance=points_service.balance(db, user_id))
    else:
        points = _award_points(db, user_id, entry_id)

    # 인식이 끝난 사진을 끼니에 붙인다. 실패해도 끼니 기록은 그대로 남는다(#699).
    photo = diet_photo_service.store_for_entry(db, user_id, entry_id, image_bytes)

    # 모델 원본 출력(raw_model_output)은 클라이언트로 내보내지 않음(디버깅 전용)
    analysis.raw_model_output = None
    return DietAnalyzeResponse(
        entry_id=entry_id,
        analysis=analysis,
        time_label=entry_time_label,
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
        raise HTTPException(status_code=404, detail="사진을 찾을 수 없어요.")
    return Response(
        content=photo.data,
        media_type=photo.content_type,
        # 사적인 이미지다 — 공유 캐시(프록시·CDN)에 남으면 안 된다. 사진 내용은
        # 바뀌지 않으므로(끼니 하나에 사진 하나) 브라우저 캐시는 길게 허용한다.
        headers={"Cache-Control": "private, max-age=86400"},
    )


@router.post("/diet/entries", response_model=DietEntryOut, status_code=201)
def create_entry(
    payload: DietEntryCreate,
    current_user: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> DietEntryOut:
    """사진 없이 회원이 직접 적은 끼니를 저장한다(#2151).

    포인트는 적립하지 않는다 — 적립은 사진 분석 저장(`/diet/analyze`)만 한다.
    기록이므로 연속 기록에는 들어간다.
    """
    try:
        return diet_service.save_manual_entry(db, current_user.id, payload)
    except diet_service.NutritionInconsistentError as e:
        raise HTTPException(status_code=422, detail=str(e)) from e
    except diet_service.IdempotencyConflictError as e:
        raise HTTPException(status_code=409, detail=str(e)) from e


@router.put("/diet/entries/{entry_id}", response_model=DietEntryOut)
def update_entry(
    entry_id: str,
    payload: DietEntryUpdate,
    current_user: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> DietEntryOut:
    """식단 기록의 끼니 분류/시간·영양소 수정(본인 소유만, 아니면 404)."""
    row = diet_service.get_owned_entry(db, current_user.id, entry_id)
    if row is None:
        raise HTTPException(status_code=404, detail="식단 기록을 찾을 수 없어요.")
    try:
        return diet_service.apply_entry_update(db, row, payload)
    except diet_service.NutritionInconsistentError as e:
        # 형식은 맞지만 값끼리 어긋난다 — 422 로 돌려준다(#1863).
        raise HTTPException(status_code=422, detail=str(e)) from e


@router.delete("/diet/entries/{entry_id}")
def delete_entry(
    entry_id: str,
    current_user: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """식단 기록 삭제. 본인 소유 엔트리만 삭제 가능(아니면 404)."""
    row = diet_service.get_owned_entry(db, current_user.id, entry_id)
    if row is None:
        raise HTTPException(status_code=404, detail="식단 기록을 찾을 수 없어요.")
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
