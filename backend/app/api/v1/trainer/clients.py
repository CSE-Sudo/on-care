"""트레이너 라우터 — 담당 고객 목록·상태와 고객 기록(식단·운동·건강 정보·조언) 열람."""
from __future__ import annotations

from datetime import date as _date
from typing import Annotated, Literal

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query,
    Response,
)
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import RequireTrainer
from app.core import clock
from app.core.locale import RequestLocale
from app.core.pagination import DEFAULT_PAGE, MAX_PAGE
from app.db.session import get_db
from app.models.models import (
    ExerciseSession,
    HealthProfile,
    TrainerClient,
    User,
)
from app.schemas.diet_api import (
    DietAdviceResponse,
    DietAdviceSentence,
    DietPeriodResponse,
    RecordSpanResponse,
    TrainerDietCandidate,
    TrainerDietPick,
    TrainerDietPickRequest,
    TrainerDietRecommendationsResponse,
)
from app.schemas.exercise_api import (
    ExercisePeriodResponse,
    ExerciseAdviceResponse,
    ExerciseSessionOut,
    ExerciseWeekResponse,
)
from app.schemas.trainer_api import (
    ClientDietEntryOut, MemberHealthProfileOut, MemberHealthProfileUpdate,
    RoutineHistoryOut,
    TrainerClientOut, TrainerClientStatusOut, TrainerClientStatusUpdate,
)
from app.services.diet_coach_inputs import effective_protein_g
from app.services import (
    diet_service,
    diet_trainer_analysis,
    diet_trainer_pick,
    exercise_service,
    health_goal_change,
    diet_photo_service,
    trainer_service,
)
from app.services.exercise_service import (
    build_current_week, monday_of_str, monday_of_this_week_str,
    pt_session_times, weekly_goals,
)
from app.api.v1.trainer._common import (
    _audit_client_read,
    _is_ymd,
    _require_client,
)


router = APIRouter(tags=["trainer"])


@router.get("/trainer/clients", response_model=list[TrainerClientOut])
def trainer_clients(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(
        DEFAULT_PAGE, ge=1, le=MAX_PAGE, description="한 번에 가져올 고객 수"
    ),
    after_id: str | None = Query(
        None, description="다음 쪽 커서 — 받은 마지막 고객의 id(회원 id)"
    ),
) -> list[TrainerClientOut]:
    """담당 고객 로스터 한 쪽. 각 카드의 오늘 영양소와 나트륨 추세는
    회원의 실제 식단 기록(DietEntry)에서 집계한다 — 트레이너↔회원 실데이터 공유.

    로스터는 트레이너 한 명이 감당하는 인원만큼만 자라 급하지 않지만, 상한이 없으면
    카드마다 붙는 집계까지 인원수에 비례해 커진다. (#980)

    커서가 다른 목록과 다르다 — 정렬키가 시각이 아니라 트레이너가 정한 순서
    (`sort_order`)이고 그 값은 카드에 실리지 않으므로, 받은 마지막 카드의 **id 하나**만
    넘기면 서버가 그 자리를 찾아 이어 준다. 명단에 없는 id 는 422 다(조용히 첫 쪽을
    돌려주면 이어 받기가 제자리를 돈다).
    """
    try:
        return trainer_service.build_roster(
            db, trainer.id, limit=limit, after_id=after_id
        )
    except trainer_service.RosterCursorNotFound as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.delete("/trainer/clients/{member_id}", status_code=204)
def trainer_remove_client(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> None:
    """담당 고객 관계만 해제한다. 회원 계정과 원본 기록은 유지한다."""
    link = db.scalar(
        select(TrainerClient).where(
            TrainerClient.trainer_id == trainer.id,
            TrainerClient.member_id == member_id,
        )
    )
    if link is None:
        raise HTTPException(status_code=404, detail="담당 고객을 찾을 수 없습니다.")
    if not link.active:
        raise HTTPException(status_code=404, detail="담당 고객을 찾을 수 없습니다.")
    trainer_service.remove_client(db, link)


@router.put("/trainer/clients/{member_id}/registration", status_code=204)
def trainer_restore_client(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> None:
    """고객 관리에 남아 있는 미등록 고객을 다시 담당으로 등록한다."""
    link = db.scalar(
        select(TrainerClient).where(
            TrainerClient.trainer_id == trainer.id,
            TrainerClient.member_id == member_id,
        )
    )
    if link is None:
        raise HTTPException(status_code=404, detail="고객을 찾을 수 없습니다.")
    try:
        trainer_service.restore_client(db, link)
    except trainer_service.ClientLinkDetached as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except trainer_service.ClientConsentRequired as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.put(
    "/trainer/clients/{member_id}/status",
    response_model=TrainerClientStatusOut,
)
def trainer_set_client_status(
    member_id: str,
    payload: TrainerClientStatusUpdate,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerClientStatusOut:
    """담당 회원을 활성/휴면으로 전환한다. (#707)

    담당 관계는 건드리지 않는다 — 휴면 회원도 기록·식단·운동·채팅이 그대로 남고
    회원 앱의 담당 코치도 그대로다. 남의 고객·없는 회원은 404(소유권 경계),
    담당이 이미 해제된 회원은 409 다.

    같은 값을 다시 보내도 200 이고 상태가 흔들리지 않는다.
    """
    link = db.scalar(
        select(TrainerClient).where(
            TrainerClient.trainer_id == trainer.id,
            TrainerClient.member_id == member_id,
        )
    )
    if link is None:
        raise HTTPException(status_code=404, detail="담당 고객을 찾을 수 없습니다.")
    try:
        return trainer_service.set_client_active(db, link, payload.active)
    except trainer_service.ClientLinkDetached as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


def _member_health_out(db: Session, member_id: str) -> MemberHealthProfileOut:
    member = db.get(User, member_id)
    profile = db.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    values = {
        field: getattr(profile, field) if profile is not None else None
        for field in (
            "height_cm",
            "weight_kg",
            "daily_calories",
            "daily_sodium_mg",
            "daily_sugar_g",
            "daily_carbs_g",
            "daily_protein_g",
            "daily_fat_g",
            # 회원 앱 마이페이지가 쓰는 현행 운동 목표(#1139) — 트레이너도 같은
            # 값을 읽고 저장한다(#1449).
            "daily_burn_kcal",
            "weekly_cardio_minutes",
            "weekly_strength_sets",
            "weekly_flexibility_minutes",
            "weekly_workout_goal",
            "weekly_exercise_minutes_goal",
            "weekly_burn_goal",
        )
    }
    return MemberHealthProfileOut(
        member_id=member_id,
        member_name=member.name if member is not None else "",
        gender=profile.gender if profile is not None else "",
        conditions=profile.conditions if profile is not None else "",
        focus_changed_by=profile.focus_changed_by if profile is not None else None,
        focus_changed_at=profile.focus_changed_at if profile is not None else None,
        effective_daily_protein_g=effective_protein_g(profile),
        notes_changed_by=profile.notes_changed_by if profile is not None else None,
        notes_changed_at=profile.notes_changed_at if profile is not None else None,
        **values,
    )


@router.get(
    "/trainer/clients/{member_id}/health-profile",
    response_model=MemberHealthProfileOut,
    dependencies=[_audit_client_read("body")],
)
def trainer_member_health_profile(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> MemberHealthProfileOut:
    _require_client(db, trainer.id, member_id)
    return _member_health_out(db, member_id)


@router.put(
    "/trainer/clients/{member_id}/health-profile",
    response_model=MemberHealthProfileOut,
)
def trainer_update_member_health_profile(
    member_id: str,
    payload: MemberHealthProfileUpdate,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> MemberHealthProfileOut:
    _require_client(db, trainer.id, member_id)
    profile = db.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    if profile is None:
        profile = HealthProfile(user_id=member_id)
        db.add(profile)
    before = profile.conditions
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(profile, field, value)
    # 승인 없이 바로 적용하되, 목표가 바뀌었으면 기록하고 회원에게 알린다(#1832).
    health_goal_change.record_trainer_change(
        db, profile, before=before, trainer=trainer, member_id=member_id
    )
    db.commit()
    return _member_health_out(db, member_id)


@router.get(
    "/trainer/clients/{member_id}/diet",
    response_model=list[ClientDietEntryOut],
    dependencies=[_audit_client_read("diet")],
)
def trainer_client_diet(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    date: str | None = Query(None, description="YYYY-MM-DD (기본: 오늘)"),
) -> list[ClientDietEntryOut]:
    """담당 고객의 식단(회원이 회원 앱에서 기록한 실제 데이터)."""
    _require_client(db, trainer.id, member_id)
    day = date or trainer_service.today_iso()
    # 형식 검증 — 잘못된 date 가 조용히 빈 목록으로 나가지 않게 422(캘린더 라우트와 일관, #278).
    if not _is_ymd(day):
        raise HTTPException(status_code=422, detail="date 는 YYYY-MM-DD 형식이어야 합니다.")
    return trainer_service.build_client_diet(db, member_id, day)


@router.get(
    "/trainer/clients/{member_id}/diet/days",
    response_model=DietPeriodResponse,
    dependencies=[_audit_client_read("diet")],
)
def trainer_client_diet_period(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    from_date: Annotated[_date | None, Query(alias="from")] = None,
    to_date: Annotated[_date | None, Query(alias="to")] = None,
) -> DietPeriodResponse:
    """담당 고객의 기간 식단 합계. 회원 API(`GET /diet/days`)와 **같은 규칙**이다.

    트레이너 화면의 기간 그래프가 회원 앱과 같은 숫자를 그리려면 같은 집계를
    읽어야 한다(#2156). `from` 을 생략하면 그 회원의 첫 기록일부터다(#2079).
    구간 상한(1100일, #2833)도 같다.
    """
    _require_client(db, trainer.id, member_id)
    return diet_service.build_period(db, member_id, start=from_date, end=to_date)


@router.get(
    "/trainer/clients/{member_id}/exercise/weeks",
    response_model=ExercisePeriodResponse,
    dependencies=[_audit_client_read("exercise")],
)
def trainer_client_exercise_period(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    from_date: Annotated[_date | None, Query(alias="from")] = None,
    to_date: Annotated[_date | None, Query(alias="to")] = None,
) -> ExercisePeriodResponse:
    """담당 고객의 기간 운동 집계. 회원 API(`GET /exercise/weeks`)와 같은 규칙이다.

    `전체` 가 모든 기록을 그리므로(#2079) 주마다 부르면 왕복이 주 수만큼 늘어난다
    (#2247). 한 주를 펼쳐 볼 때는 그대로 `GET .../exercise-week?week_start=` 다.
    구간 상한(160주, #2833)도 같다.
    """
    _require_client(db, trainer.id, member_id)
    profile = db.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    data = exercise_service.build_period(
        db,
        member_id,
        start=from_date,
        end=to_date,
        goals=weekly_goals(profile),
    )
    return ExercisePeriodResponse(**data)


@router.get(
    "/trainer/clients/{member_id}/records/span",
    response_model=RecordSpanResponse,
    dependencies=[_audit_client_read("exercise")],
)
def trainer_client_record_span(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> RecordSpanResponse:
    """담당 고객이 식단·운동을 처음 남긴 날. 회원 API(`GET /me/records/span`)와 같다."""
    _require_client(db, trainer.id, member_id)
    return RecordSpanResponse(
        diet_first_date=diet_service.first_entry_date(db, member_id),
        exercise_first_date=exercise_service.first_session_date(db, member_id),
    )


@router.get(
    "/trainer/clients/{member_id}/diet/photos/{photo_id}",
    dependencies=[_audit_client_read("diet")],
)
def trainer_client_diet_photo(
    member_id: str,
    photo_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> Response:
    """담당 고객이 올린 끼니 사진. (#699)

    두 겹으로 막는다: 담당 링크가 없으면 404(다른 트레이너의 고객), 링크가 있어도
    사진이 그 회원의 것이 아니면 404. 사진 id 를 알아도 담당이 아니면 열리지 않고,
    담당이어도 남의 고객 사진은 열리지 않는다.
    """
    _require_client(db, trainer.id, member_id)
    photo = diet_photo_service.get_owned_photo(db, photo_id, member_id)
    if photo is None:
        raise HTTPException(status_code=404, detail="사진을 찾을 수 없습니다.")
    return Response(
        content=photo.data,
        media_type=photo.content_type,
        # 회원의 사적인 사진이다 — 공유 캐시에 남기지 않는다(회원 경로와 동일).
        headers={"Cache-Control": "private, max-age=86400"},
    )


@router.get(
    "/trainer/clients/{member_id}/history",
    response_model=list[RoutineHistoryOut],
    dependencies=[_audit_client_read("exercise")],
)
def trainer_client_history(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[RoutineHistoryOut]:
    """담당 고객의 운동 완료 기록(최신순). 타 트레이너 기록/메모는 제외한다."""
    _require_client(db, trainer.id, member_id)
    return trainer_service.build_client_history(db, member_id, trainer.id)


@router.get(
    "/trainer/clients/{member_id}/diet-advice",
    response_model=DietAdviceResponse,
    dependencies=[_audit_client_read("diet")],
)
def trainer_client_diet_advice(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    locale: RequestLocale,
    period: Annotated[
        Literal["today", "week", "all"],
        Query(description="조언이 다룰 구간 — 회원 앱 기간 토글과 같은 이름"),
    ] = "today",
) -> DietAdviceResponse:
    """담당 고객의 기간별 `식단 분석` — 원인까지 짚는 서술형 규칙 문장. (#2379)

    회원 앱 조언과 **같은 기간·같은 판정**이다(이번 주는 월·화 지난주 회고 포함,
    전체는 최근 4주). 같은 회원의 같은 기간을 두 화면이 다른 기준으로 말하면 상담에서
    둘이 서로 다른 이야기를 들고 앉게 된다. AI 는 부르지 않는다 — 회원 앱 조언의 AI
    문장은 회원에게 하는 말이다. 문장은 `sentences` 의 키·값으로 트레이너 웹이 그린다.
    """
    _require_client(db, trainer.id, member_id)
    result = diet_trainer_analysis.analysis(db, member_id, period, now=clock.now())
    return DietAdviceResponse(
        period=result.period,
        from_date=result.from_date,
        to_date=result.to_date,
        days_logged=result.days_logged,
        message=result.message_in(locale),
        sentences=[
            DietAdviceSentence(key=s.key, params=s.params) for s in result.sentences
        ],
    )


def _diet_pick_out(pick) -> TrainerDietPick:
    return TrainerDietPick(
        slot=pick.slot,
        name=pick.name,
        tag=pick.tag,
        keyword=pick.keyword,
        status=diet_trainer_pick.status_of(pick),
        confirmed_at=pick.confirmed_at.isoformat(),
        resolved_at=pick.resolved_at.isoformat() if pick.resolved_at else None,
    )


def _diet_recommendations(
    db: Session, trainer_id: str, member_id: str, locale: str
) -> TrainerDietRecommendationsResponse:
    pick = diet_trainer_pick.current(db, member_id, trainer_id)
    exclude = {diet_trainer_pick.norm(pick.name)} if pick is not None else set()
    found = diet_trainer_pick.candidates(db, member_id, lang=locale, exclude=exclude)
    return TrainerDietRecommendationsResponse(
        needs=found.needs,
        basis_days=found.basis_days,
        pick=_diet_pick_out(pick) if pick is not None else None,
        candidates=[
            TrainerDietCandidate(
                slot=c.menu.slot, name=c.menu.name, tag=c.menu.tag,
                keyword=c.menu.keyword, kcal=c.menu.kcal,
                protein_g=c.menu.protein_g, sodium_mg=c.menu.sodium_mg,
                urgent=c.urgent,
            )
            for c in found.items
        ],
    )


@router.get(
    "/trainer/clients/{member_id}/diet-recommendations",
    response_model=TrainerDietRecommendationsResponse,
    dependencies=[_audit_client_read("diet")],
)
def trainer_client_diet_recommendations(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    locale: RequestLocale,
) -> TrainerDietRecommendationsResponse:
    """담당 회원에게 추천할 AI 식단 후보와 지금 확정한 추천. (#2378)

    후보는 회원의 4주 추천 메뉴 리스트에서 급한 태그를 채우는 메뉴부터다. 저장된
    리스트를 읽기만 하므로 후보를 넘겨 봐도 AI 를 새로 부르지 않는다.
    """
    _require_client(db, trainer.id, member_id)
    return _diet_recommendations(db, trainer.id, member_id, locale)


@router.put(
    "/trainer/clients/{member_id}/diet-recommendations",
    response_model=TrainerDietRecommendationsResponse,
)
def trainer_confirm_diet_recommendation(
    member_id: str,
    payload: TrainerDietPickRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    locale: RequestLocale,
) -> TrainerDietRecommendationsResponse:
    """후보 하나를 회원에게 추천한다 — 회원 앱 홈 `추천 식단` 첫 장이 된다. (#2378)

    다시 부르면 바꾸기다(회원당 한 건). 지금 후보 리스트에 없는 메뉴는 422.
    """
    _require_client(db, trainer.id, member_id)
    try:
        diet_trainer_pick.confirm(
            db, member_id, trainer.id,
            name=payload.name, slot=payload.slot, lang=locale,
        )
    except diet_trainer_pick.PickNotInPlan as exc:
        raise HTTPException(
            status_code=422, detail="추천 후보에 없는 메뉴입니다."
        ) from exc
    return _diet_recommendations(db, trainer.id, member_id, locale)


@router.get(
    "/trainer/clients/{member_id}/exercise-advice",
    response_model=ExerciseAdviceResponse,
    dependencies=[_audit_client_read("exercise")],
)
def trainer_client_exercise_advice(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    period: Annotated[
        Literal["today", "week", "all"],
        Query(description="조언이 다룰 구간 — 화면 기간 토글과 같은 이름"),
    ] = "today",
) -> ExerciseAdviceResponse:
    """담당 고객의 기간별 운동 조언. 식단 조언(#1017)과 같은 규칙이다. (#1025)

    운동 기록은 날짜가 아니라 (그 주 월요일, 요일) 로 저장되므로, 구간이 걸치는
    주를 모두 읽어 온 뒤 실제 날짜로 되돌려 거른다.
    """
    _require_client(db, trainer.id, member_id)
    # 조회·집계는 회원 앱과 **같은 함수**다(#1574) — 규칙이 갈리면 같은 회원의
    # 같은 기간을 두 화면이 다른 날부터 세게 된다.
    start, end, days = exercise_service.period_days(db, member_id, period)
    # 추천 개인운동 기준 조언(#2162)도 회원 앱과 같은 함수로 읽는다.
    routine_days = trainer_service.advice_routine_days(db, member_id, period)
    advice = exercise_service.period_advice(days, period, routine_days)
    return ExerciseAdviceResponse(
        period=period,
        from_date=start,
        to_date=end,
        days_logged=len(days),
        message=advice.text_for(),
        advice_key=advice.key,
        advice_params=advice.params,
    )


@router.get(
    "/trainer/clients/{member_id}/exercise-week",
    response_model=ExerciseWeekResponse,
    dependencies=[_audit_client_read("exercise")],
)
def trainer_client_exercise_week(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    week_start: Annotated[
        str | None, Query(description="조회할 주의 월요일 YYYY-MM-DD (기본: 이번 주)")
    ] = None,
) -> ExerciseWeekResponse:
    """담당 고객의 한 주 운동 집계. `week_start` 없이 부르면 이번 주다.

    회원 API(`/exercise/weeks/current`)와 **같은 규칙**이다 — 트레이너 화면이
    `이번 달` 처럼 한 주를 넘는 기간을 그리려면 지난 주도 같은 모양으로 읽을 수
    있어야 하는데, 여기만 이번 주로 고정돼 있었다. 월요일이 아닌 날짜를 주면
    그 날이 속한 주의 월요일로 맞춘다.
    """
    _require_client(db, trainer.id, member_id)
    if week_start is None:
        week_start = monday_of_this_week_str()
    else:
        # 형식이 틀리면 조용히 이번 주로 흘려보내지 않는다 — 화면이 엉뚱한 주를
        # 그리고도 맞다고 믿게 된다(회원 API 와 같은 422).
        if not _is_ymd(week_start):
            raise HTTPException(
                status_code=422, detail="week_start 는 YYYY-MM-DD 형식이어야 합니다."
            )
        week_start = monday_of_str(week_start)
    rows = db.scalars(
        select(ExerciseSession).where(
            ExerciseSession.user_id == member_id,
            ExerciseSession.week_start == week_start,
        )
    ).all()
    # 회원 앱과 같은 연속 일수 — 운동만 센다.
    data = build_current_week(list(rows), pt_session_times(db, rows))
    profile = db.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    goal_minutes, goal_calories = weekly_goals(profile)
    return ExerciseWeekResponse(
        sessions=[ExerciseSessionOut(**row) for row in data.pop("sessions")],
        weekly_goal_minutes=goal_minutes,
        weekly_goal_calories=goal_calories,
        **data,
    )
