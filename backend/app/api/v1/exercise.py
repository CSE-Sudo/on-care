"""
운동 라우터 — 프론트 계약 정렬.

  GET  /exercise/weeks/current   -> 이번 주 운동 집계(요일별/타입별 + streak + 코칭)
  POST /exercise/sessions        -> 운동 기록 추가 (집계에 반영)
  POST /exercise/calories        -> 운동 이름·시간·강도로 소모 칼로리 미리보기
"""
from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser
from app.core import clock
from app.db.session import get_db
from app.models.models import ExerciseSession, HealthProfile
from app.schemas.exercise_api import (
    ExerciseAdviceResponse, ExerciseCalorieRequest, ExerciseCalorieResponse,
    ExerciseSessionCreate, ExerciseSessionCreatedOut, ExerciseSessionOut,
    ExerciseWeekResponse,
)
from app.schemas.points_api import PointsOut
from app.services import (
    exercise_activity, exercise_service, exercise_types, points_service,
    streak_shield_service, trainer_service,
)
from app.services.coach import personal_ingest
from app.services.exercise_service import (
    weekly_goals,
    WEEKDAY_LABELS, build_current_week, monday_of_str, monday_of_this_week_str,
    session_date_of,
)

router = APIRouter(tags=["exercise"])


def _session_date(row: ExerciseSession) -> str:
    """세션의 실제 날짜 YYYY-MM-DD. 저장은 (주 시작 + 요일 라벨)로 쪼개져 있다.

    적재 문구에 날짜를 넣으려면 되돌려야 한다 — "월요일"만 적으면 몇 주 전 기록도
    똑같이 보여 코치가 최근 것과 구분하지 못한다.
    """
    resolved = session_date_of(row)
    return resolved.isoformat() if resolved else row.week_start

def _reject_if_derived(row: ExerciseSession) -> None:
    """트레이너 PT/배정 루틴에서 파생된 기록은 회원이 고칠 수 없다. (#499, #638)

    404 가 아니라 409 다 — 기록은 분명히 존재하고 회원 것이며, 화면에도 보인다.
    없는 척하면 앱이 목록에서 사라진 줄 알고 잘못 갱신한다. 삭제하려면 트레이너가
    그 세션을 지워야 하고, 그러면 이 기록도 함께 사라진다.
    """
    if row.source != "member":
        raise HTTPException(
            status_code=409,
            detail="코칭에서 생성된 운동 기록은 수정하거나 삭제할 수 없습니다.",
        )


@router.get("/exercise/weeks/current", response_model=ExerciseWeekResponse)
def current_week(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    week_start: Annotated[str | None, Query(description="조회할 주의 월요일 YYYY-MM-DD")] = None,
) -> ExerciseWeekResponse:
    """한 주의 운동 집계. `week_start` 없이 부르면 이번 주다.

    회원 앱이 지난 날짜를 고르면 그 주를 받아 하루치를 보여준다. 이 파라미터가
    없을 때는 조회 경로가 이번 주 하나뿐이라 지난 기록을 볼 방법이 없었다.
    월요일이 아닌 날짜를 줘도 그 날이 속한 주로 맞춘다.
    """
    if week_start is None:
        week_start = monday_of_this_week_str()
    else:
        # strptime 으로 엄격하게 본다. date.fromisoformat 은 3.11 부터
        # `20260810` 같은 기본 형식도 받아, 앱의 로컬 목업(엄격한 YYYY-MM-DD)과
        # 받아들이는 값의 집합이 갈린다.
        try:
            datetime.strptime(week_start, "%Y-%m-%d")
        except ValueError:
            raise HTTPException(
                status_code=422, detail="week_start 는 YYYY-MM-DD 형식이어야 합니다."
            ) from None
        week_start = monday_of_str(week_start)
    rows = db.scalars(
        select(ExerciseSession)
        .where(ExerciseSession.user_id == current_user.id)
        .where(ExerciseSession.week_start == week_start)
    ).all()
    data = build_current_week(list(rows))
    profile = db.scalar(
        select(HealthProfile).where(HealthProfile.user_id == current_user.id)
    )
    goal_minutes, goal_calories = weekly_goals(profile)
    return ExerciseWeekResponse(
        sessions=[ExerciseSessionOut(**s) for s in data.pop("sessions")],
        weekly_goal_minutes=goal_minutes,
        weekly_goal_calories=goal_calories,
        **data,
    )


@router.get("/exercise/advice", response_model=ExerciseAdviceResponse)
def exercise_advice(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    period: Annotated[
        Literal["today", "week", "all"],
        Query(description="조언이 다룰 구간 — 화면의 기간 토글과 같은 이름"),
    ] = "today",
) -> ExerciseAdviceResponse:
    """기간에 맞는 운동 조언. (#1574)

    식단 조언(`/diet/advice`, #1017)과 같은 규칙이다 — 두 카드가 같은 자리에서
    같은 토글을 따라가므로, 한쪽만 오늘 이야기로 남으면 회원은 `이번 주` 를 보며
    "오늘은 유산소를 했네요" 를 읽게 된다.

    조언 문장은 트레이너웹이 보는 것과 **같다**(#1025) — 회원과 코치가 같은
    회원의 같은 기간을 두고 다른 이야기를 들고 앉으면 안 된다.

    경계도 앱이 아니라 서버가 정한다.

    오늘 걸린 추천 개인운동이 있으면 그 목록과 날짜별 완료를 기준으로 말한다
    (#2162) — 읽는 구간은 트레이너웹과 같은 함수가 정한다.
    """
    start, end, days = exercise_service.period_days(db, current_user.id, period)
    routine_days = trainer_service.advice_routine_days(db, current_user.id, period)
    return ExerciseAdviceResponse(
        period=period,
        from_date=start,
        to_date=end,
        days_logged=len(days),
        message=exercise_service.period_coach_message(days, period, routine_days),
    )


def _strength_only(normalized_type: str, value):
    """근력에서만 의미 있는 값(세트·횟수·중량). 다른 유형에서 온 값은 버린다. (#1262)

    유산소를 세트로 세는 화면은 없다 — 받아 두면 집계가 읽지 않는 값이 기록에만
    남아, 나중에 그 값을 믿는 화면이 생겼을 때 조용히 어긋난다.
    """
    if normalized_type != exercise_types.STRENGTH:
        return None
    return value


def _weight_for(normalized_type: str, weight: float | None) -> float | None:
    """저장할 중량. 근력만, 소수점 한 자리로 맞춘다. (#1276)"""
    value = _strength_only(normalized_type, weight)
    return None if value is None else round(value, 1)


def _reps_and_hold(
    normalized_type: str, payload: ExerciseSessionCreate
) -> tuple[int | None, int | None]:
    """(횟수, 홀드 초). 한 세트는 회로든 초로든 **한 번만** 잰다. (#1969)

    버티는 운동이면 초가 맞고 횟수는 비운다. 둘 다 오면 초를 믿는다 — 초를 보내는
    클라이언트는 이 칸을 아는 쪽이고, 횟수는 칸이 없던 시절처럼 초를 억지로 담아
    보낸 값일 수 있다(`reps: 3` 으로 적힌 45초 홀드가 그렇게 생겼다).

    세트·중량과 같은 규칙으로 근력이 아니면 둘 다 버린다.
    """
    hold = _strength_only(normalized_type, payload.hold_seconds)
    reps = _strength_only(normalized_type, payload.reps)
    return (None, hold) if hold is not None else (reps, None)


def _placement(day: date | None) -> tuple[str, str, datetime]:
    """(주 시작 월요일, 요일 라벨, 완료 시각). 날짜가 없으면 오늘이다.

    한 스냅샷에서 셋을 함께 뽑는다 — 따로 읽으면 KST 자정 사이에 저장된 한
    세션의 요일과 주차가 서로 다른 날을 가리킬 수 있다.

    `completed_at` 을 여기서 같이 정하는 이유는 그 값이 **적은 날이 아니라 한
    날**이어야 하기 때문이다(#1264). 저장 시각(`clock.now()`)을 쓰면 어제 운동을
    오늘 적었을 때 회원 화면은 어제로, 시각을 읽는 쪽은 오늘로 갈린다. 정오인
    까닭은 [exercise_activity.noon] 에 적어 두었다.
    """
    target = day or clock.today()
    return (
        monday_of_str(target.isoformat()),
        WEEKDAY_LABELS[target.weekday()],
        exercise_activity.noon(target),
    )


def _calories_for(
    db: Session,
    user_id: str,
    payload: ExerciseSessionCreate,
    exercise_type: str,
):
    """저장할 소모 칼로리와 그 근거. **클라이언트가 보낸 값은 쓰지 않는다.**

    수기 기록의 칼로리는 오랫동안 앱이 계산해 보낸 값이었다. 그래서 같은 운동이
    앱과 서버에서 다른 값으로 적힐 수 있었고, 이름·체중을 반영하려면 두 곳을
    같이 고쳐야 했다. 이제 계산은 서버 하나다(#1312) — 앱이 화면에 띄우는
    미리보기도 `POST /exercise/calories` 로 같은 계산을 받아 오므로, 저장 뒤에
    숫자가 달라지지 않는다.
    """
    return exercise_service.estimate(
        db,
        name=payload.name,
        type_=exercise_type,
        minutes=payload.minutes,
        intensity=payload.intensity,
        weight_kg=exercise_service.member_weight_kg(db, user_id),
    )


@router.post("/exercise/calories", response_model=ExerciseCalorieResponse)
def preview_calories(
    payload: ExerciseCalorieRequest,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> ExerciseCalorieResponse:
    """운동 이름·시간·강도로 소모 칼로리 미리보기. (#1312)

    저장 경로와 **같은 계산**이다. 폼이 이 값을 그대로 보여 주고 서버가 저장할 때
    다시 계산하므로, 화면의 숫자와 기록의 숫자가 갈리지 않는다.

    이름이 비어 있으면 400 이다 — 이름 없이 확정된 숫자를 내주지 않는 것이 이
    계산의 요점이다. 이름이 있어도 종목표에 붙지 않으면 유형 평균이 나오고,
    그때는 `source` 가 `estimate` 라 화면이 어림값으로 표시할 수 있다.
    """
    if not payload.name.strip():
        raise HTTPException(status_code=400, detail="운동 이름을 입력해 주세요.")
    result = exercise_service.estimate(
        db,
        name=payload.name,
        type_=payload.type,
        minutes=payload.minutes,
        intensity=payload.intensity,
        weight_kg=exercise_service.member_weight_kg(db, current_user.id),
    )
    return ExerciseCalorieResponse(
        calories=result.calories,
        source=result.source,
        matched_name=result.matched_name,
        isometric=exercise_service.isometric_default(db, payload.name),
    )


@router.post(
    "/exercise/sessions", response_model=ExerciseSessionCreatedOut, status_code=201
)
def add_session(
    payload: ExerciseSessionCreate,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> ExerciseSessionCreatedOut:
    # type·intensity·date·minutes·calories 는 모두 ExerciseSessionCreate 의
    # 타입·Field 제약에서 422 로 걸린다 — minutes 의 상한도 그 안에 있다(#1903).
    # 예전에는 이 주석이 말하는 것과 달리 minutes 만 상한이 없어, 앱을 거치지
    # 않은 호출이 넣은 값이 주간 집계로 그대로 번졌다.
    week_start, day_label, completed_at = _placement(payload.date)
    normalized = exercise_types.normalize(payload.type)
    estimated = _calories_for(db, current_user.id, payload, normalized)
    reps, hold_seconds = _reps_and_hold(normalized, payload)
    row = ExerciseSession(
        id=f"ex-{uuid.uuid4().hex[:12]}",
        user_id=current_user.id,
        week_start=week_start,
        day_label=day_label,
        type=normalized,
        name=payload.name.strip(),
        minutes=payload.minutes,
        duration_seconds=payload.duration_seconds,
        sets=_strength_only(normalized, payload.sets),
        reps=reps,
        hold_seconds=hold_seconds,
        weight=_weight_for(normalized, payload.weight),
        calories=estimated.calories,
        calorie_source=estimated.source,
        intensity=payload.intensity,
        # 세 날짜 필드가 같은 날을 가리킨다 — 하나만 채우면 읽는 자리마다 다른
        # 날짜를 본다. (#1264)
        completed_at=completed_at,
    )
    db.add(row)
    # 회원이 직접 추가한 운동은 포인트를 받는다(#1786). 기록과 같은 트랜잭션이라
    # 기록만 남고 적립이 빠지거나 그 반대가 되지 않는다. 적립이 행을 참조하므로
    # 먼저 flush 한다.
    db.flush()
    points = points_service.award(
        db, current_user.id, points_service.EXERCISE_MANUAL, row.id
    )
    # 보호권으로 이어 붙인 날에 운동 기록이 생기면 그 보호권을 되돌린다(#1788).
    streak_shield_service.refund_for_record(
        db, current_user.id, exercise_activity.activity_date_of(row)
    )
    db.commit()
    db.refresh(row)

    # 단건 응답도 프론트 표시 형식(date_label/time_label/items)을 채워 반환
    one = build_current_week([row])["sessions"][0]
    out = ExerciseSessionCreatedOut(**one, points=PointsOut.of(points))
    # 응답을 다 만든 뒤 적재한다(#586). 실패하면 personal_ingest 가 세션을 롤백하는데,
    # 그때 row 가 만료되면 적재 실패가 기록 저장 실패로 번진다. 커밋은 이미 끝났다.
    personal_ingest.record_exercise(
        db, current_user.id, date=_session_date(row), exercise_type=row.type,
        minutes=row.minutes, calories=row.calories, intensity=row.intensity,
        source_ref=row.id,
    )
    return out


@router.put("/exercise/sessions/{session_id}", response_model=ExerciseSessionOut)
def update_session(
    session_id: str,
    payload: ExerciseSessionCreate,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> ExerciseSessionOut:
    """운동 기록 수정(본인 소유만, 아니면 404). 유형/이름/시간/칼로리/강도/날짜 갱신."""
    row = db.scalar(
        select(ExerciseSession)
        .where(ExerciseSession.id == session_id)
        .where(ExerciseSession.user_id == current_user.id)
    )
    if row is None:
        raise HTTPException(status_code=404, detail="운동 기록을 찾을 수 없습니다.")
    _reject_if_derived(row)

    # 날짜를 주지 않은 수정은 원래 있던 자리를 그대로 둔다 — 오늘로 끌어오면
    # 지난 기록을 고치기만 해도 이번 주로 옮겨 간다.
    if payload.date is not None:
        # 옮길 때도 셋을 함께 옮긴다 — `completed_at` 만 옛 날짜에 남으면 그
        # 기록의 날짜가 화면과 다른 곳에서 갈린다. (#1264)
        row.week_start, row.day_label, row.completed_at = _placement(payload.date)

    row.type = exercise_types.normalize(payload.type)
    row.name = payload.name.strip()
    row.minutes = payload.minutes
    row.duration_seconds = payload.duration_seconds
    row.sets = _strength_only(row.type, payload.sets)
    row.reps, row.hold_seconds = _reps_and_hold(row.type, payload)
    row.weight = _weight_for(row.type, payload.weight)
    estimated = _calories_for(db, current_user.id, payload, row.type)
    row.calories = estimated.calories
    row.calorie_source = estimated.source
    row.intensity = payload.intensity
    # 기록을 보호권으로 이어 붙인 날로 옮겼으면 그 보호권을 되돌린다(#1788).
    streak_shield_service.refund_for_record(
        db, current_user.id, exercise_activity.activity_date_of(row)
    )
    db.commit()
    db.refresh(row)

    one = build_current_week([row])["sessions"][0]
    out = ExerciseSessionOut(**one)
    # 30분을 45분으로 고쳤으면 코치도 45분으로 알아야 한다(#603). 값을 넘기지 않고
    # id 만 넘기는 이유는 #614 — 갱신은 잠금 안에서 행을 다시 읽어야, 두 수정이
    # 역순으로 도착해도 최종 문서가 DB 최신값과 어긋나지 않는다.
    personal_ingest.refresh_exercise(db, current_user.id, session_id=row.id)
    return out


@router.delete("/exercise/sessions/{session_id}")
def delete_session(
    session_id: str,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """운동 기록 삭제. 본인 소유 세션만 삭제 가능(아니면 404)."""
    row = db.scalar(
        select(ExerciseSession)
        .where(ExerciseSession.id == session_id)
        .where(ExerciseSession.user_id == current_user.id)
    )
    if row is None:
        raise HTTPException(status_code=404, detail="운동 기록을 찾을 수 없습니다.")
    _reject_if_derived(row)
    # 이 기록으로 받은 포인트를 회수한다 — 삭제와 같은 트랜잭션이다(#1786).
    points_service.revoke(
        db, current_user.id, points_service.SOURCE_EXERCISE_SESSION, row.id
    )
    db.delete(row)
    db.commit()
    personal_ingest.forget(db, current_user.id, session_id)
    return {"status": "deleted"}
