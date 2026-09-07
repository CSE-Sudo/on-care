"""
트레이너 라우터 — 트레이너 앱 전용(role == 'trainer').

  GET /trainer/me   -> 로그인한 트레이너의 프로필(Figma MY / seedTrainerProfile)

이후 이슈에서 /trainer/clients, /trainer/clients/{id}/diet(회원 실데이터 공유),
채팅·루틴·스케줄이 이 라우터에 추가된다. 모든 엔드포인트는 RequireTrainer 로
보호되며 데모 폴백이 없다(회원 데모 사용자 유입 차단).
"""
from __future__ import annotations

import json
import re
from datetime import date as _date
from datetime import datetime
from pathlib import PurePath
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Response, UploadFile
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.api.deps import RequireTrainer
from app.core.config import get_settings
from app.core.pagination import DEFAULT_PAGE, MAX_PAGE, parse_before
from app.core.rate_limit import limiter, rate_limit
from app.core.security import hash_password, verify_password
from app.db.session import get_db
from app.models.models import (
    ChatMessage,
    ExerciseSession,
    HealthProfile,
    Notification,
    TrainerClient,
    TrainerProfile,
    User,
)
from app.schemas.diet_api import DietAdviceResponse
from app.schemas.exercise_api import (
    ExerciseAdviceResponse,
    ExerciseSessionOut,
    ExerciseWeekResponse,
)
from app.schemas.consultation_api import (
    ConsultationAccept,
    ConsultationAcceptOut,
    ConsultationDecision,
    ConsultationStatusFilter,
    TrainerConsultationOut,
)
from app.schemas.trainer_api import (
    ChatMessageOut, ChatSendRequest, ClientCoachMessageOut, ClientCoachOut,
    ClientCoachRequest, ClientDietEntryOut,
    DashboardCoachingSummaryOut,
    MemberHealthProfileOut, MemberHealthProfileUpdate,
    ReportFeedbackOut,
    ReportFeedbackSaveRequest,
    ReportSendRequest, ReportSummaryOut,
    RoutineAssignRequest, RoutineOut, RoutineHistoryOut,
    RoutineFeedbackRequest,
    RoutineSuggestionApproveRequest, RoutineSuggestionCreateRequest,
    ProgramAssignRequest,
    RoutineOptionsOut, RoutineOptionsRequest, RoutineUpdateRequest,
    ScheduleCancelRequest, ScheduleCompleteRequest,
    ScheduleProgramSendRequest, ScheduleCreateRequest, ScheduleProgramRegisterOut,
    ScheduleRecurringPreviewOut, ScheduleRecurringRequest, ScheduleReopenRequest,
    ScheduleProgramRegisterRequest, ScheduleSessionOut, ScheduleUpdateRequest,
    PairedMemberOut,
    PairingCodeRedeem,
    TrainerClientInviteCreate, TrainerClientInviteOut,
    TrainerClientOut, TrainerClientStatusOut, TrainerClientStatusUpdate,
    FollowUpScope,
    TrainerFollowUpTaskCreateRequest, TrainerFollowUpTaskOut,
    TrainerFollowUpTaskUpdateRequest,
    TrainerGymAffiliation, TrainerMe, TrainerMeUpdate,
    TrainerMemoCreateRequest, TrainerMemoOut, TrainerMemoUpdateRequest,
    TrainerProgramDraftCreate, TrainerProgramDraftOut,
    TrainerProgramDraftSummary, TrainerProgramDraftUpdate,
    TrainerProgramTemplateCreate, TrainerProgramTemplateOut,
    TrainerProgramTemplateUpdate,
    TrainerNotificationOut, TrainerNotificationSettings, TrainerNotificationSettingsUpdate,
    TrainerPasswordChange, WeeklyReportOut,
)
from app.services import (
    diet_service,
    exercise_service,
    chat_image_storage,
    consultation_service,
    member_pairing_service,
    trainer_client_invite_service,
    trainer_program_template_service,
    diet_photo_service,
    notification_service,
    trainer_dashboard_coaching_service,
    trainer_report_summary_service,
    report_pdf_storage,
    trainer_routine_options_service,
    trainer_service,
)
from app.services.coach import conversation
from app.services.exercise_service import (
    build_current_week, monday_of_str, monday_of_this_week_str, weekly_goals,
)
from app.services.coach.chat import answer as coach_answer

router = APIRouter(tags=["trainer"])

#: 알림함이 한 번에 내려주는 최대 건수. 회원 이력과 같은 이유로 상한을 둔다 —
#: 오래된 알림 무제한 로드를 막는다.
_NOTIFICATION_LIMIT = 100

# 계약 형식은 정확히 YYYY-MM-DD. date.fromisoformat 는 3.11+ 에서 basic ISO·주 날짜도 받으므로
# 정규식으로 먼저 좁힌 뒤 달력 유효성을 확인한다(schedule 라우트와 동일 규약).
_YMD_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def _is_ymd(v: str) -> bool:
    if not _YMD_RE.fullmatch(v):
        return False
    try:
        _date.fromisoformat(v)
        return True
    except ValueError:
        return False


def _require_profile(db: Session, trainer_id: str) -> TrainerProfile:
    profile = db.scalar(
        select(TrainerProfile).where(TrainerProfile.trainer_id == trainer_id)
    )
    if profile is None:
        raise HTTPException(status_code=404, detail="트레이너 프로필이 없습니다.")
    return profile


def _require_client(db: Session, trainer_id: str, member_id: str) -> TrainerClient:
    """(trainer, member) 담당 링크를 확인. 남의 고객/미담당이면 404(소유권 경계)."""
    link = db.scalar(
        select(TrainerClient).where(
            TrainerClient.trainer_id == trainer_id,
            TrainerClient.member_id == member_id,
        )
    )
    if link is None:
        raise HTTPException(status_code=404, detail="담당 고객을 찾을 수 없습니다.")
    return link


def _decide(
    action,
    db: Session,
    trainer_id: str,
    consultation_id: str,
    payload: ConsultationDecision,
) -> TrainerConsultationOut:
    """승인·거절 공통 예외 매핑. 두 라우트가 같은 실패 모드를 갖는다. (#467)

    남의 요청을 404 로 돌리는 것은 의도다 — 403 은 그 id 의 요청이 존재한다는
    사실을 알려 주어 id 를 훑는 것만으로 남의 상담 건수를 셀 수 있다.
    """
    try:
        return action(db, trainer_id, consultation_id, payload.note)
    except consultation_service.ConsultationNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except consultation_service.ConsultationAlreadyDecided as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except consultation_service.MemberAlreadyCoached as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.get("/trainer/me", response_model=TrainerMe)
def trainer_me(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerMe:
    profile = _require_profile(db, trainer.id)
    return trainer_service.build_trainer_me(trainer, profile)


@router.put("/trainer/me", response_model=TrainerMe)
def trainer_update_me(
    payload: TrainerMeUpdate,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerMe:
    """프로필 부분 수정. 보낸 필드만 반영하고, 이름/이메일은 계정 소관이라 건드리지 않는다."""
    profile = _require_profile(db, trainer.id)
    fields = payload.model_dump(exclude_unset=True)
    if not fields:
        # 빈 PATCH 를 성공으로 처리하면 클라이언트가 저장됐다고 오해한다.
        raise HTTPException(status_code=400, detail="수정할 항목이 없습니다.")
    try:
        return trainer_service.update_trainer_profile(db, trainer, profile, fields)
    except trainer_service.GymTextLockedByAffiliation as e:
        # 값이 틀린 게 아니라 소속이 설정된 상태와 충돌하는 것이라 422 가 아니라 409.
        raise HTTPException(
            status_code=409,
            detail="소속 헬스장이 설정돼 있어 헬스장 정보를 직접 수정할 수 없습니다. "
                   "PUT /trainer/me/gym 으로 소속을 바꾸세요.",
        ) from e


@router.put("/trainer/me/gym", response_model=TrainerMe)
def trainer_set_gym(
    payload: TrainerGymAffiliation,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerMe:
    """소속 헬스장 설정·변경. (#452)

    시드(`seed_gyms`)의 이름 매칭 백필 말고는 `gym_id` 를 채울 길이 없었다. 자기
    프로필만 바꿀 수 있고(`RequireTrainer` 가 토큰의 트레이너로 고정), 실재하는
    fitness Place 가 아니면 404 다.
    """
    profile = _require_profile(db, trainer.id)
    me = trainer_service.set_trainer_gym(db, trainer, profile, payload.gym_id)
    if me is None:
        raise HTTPException(status_code=404, detail="헬스장을 찾을 수 없습니다.")
    return me


@router.delete("/trainer/me/gym", response_model=TrainerMe)
def trainer_clear_gym(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerMe:
    """소속 해제. 원래 소속이 없어도 200 — 해제는 두 번 눌러도 오류가 아니다.

    갱신된 프로필을 그대로 돌려주므로 클라이언트가 다시 GET 하지 않아도 된다.
    """
    profile = _require_profile(db, trainer.id)
    return trainer_service.clear_trainer_gym(db, trainer, profile)


@router.post("/trainer/me/password", status_code=200)
def trainer_change_password(
    payload: TrainerPasswordChange,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """비밀번호 변경. 현재 비밀번호가 맞아야 하고, 같은 값으로는 바꿀 수 없다."""
    if not verify_password(payload.current_password, trainer.hashed_password):
        # 현재 비밀번호 불일치는 401 이 아니라 400 — 토큰은 유효하므로
        # 클라이언트가 로그아웃 처리로 오인하면 안 된다.
        raise HTTPException(status_code=400, detail="현재 비밀번호가 일치하지 않습니다.")
    if verify_password(payload.new_password, trainer.hashed_password):
        raise HTTPException(status_code=400, detail="현재와 다른 비밀번호를 입력해 주세요.")
    trainer.hashed_password = hash_password(payload.new_password)
    db.commit()
    return {"status": "changed"}


@router.delete("/trainer/me")
def trainer_delete_me(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """트레이너 탈퇴. 담당 회원에게 알린 뒤 계정과 딸린 데이터를 지운다. (#505)

    회원 탈퇴(`DELETE /users/me`)와 대칭이다. 담당 회원이 남아 있어도 막지 않는다 —
    막으면 담당이 있는 트레이너는 계정을 영영 지울 수 없다.
    """
    trainer_service.delete_trainer_account(db, trainer)
    return {"status": "deleted"}


@router.get("/trainer/me/settings", response_model=TrainerNotificationSettings)
def trainer_settings(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerNotificationSettings:
    """알림 수신 설정. 기본값은 서버가 소유한다 — 클라이언트마다 기본값을
    들고 있으면 기기별로 갈라진다."""
    return trainer_service.build_notification_settings(
        _require_profile(db, trainer.id)
    )


@router.put("/trainer/me/settings", response_model=TrainerNotificationSettings)
def trainer_update_settings(
    payload: TrainerNotificationSettingsUpdate,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerNotificationSettings:
    """알림 수신 설정 부분 수정."""
    fields = payload.model_dump(exclude_unset=True)
    if not fields:
        raise HTTPException(status_code=400, detail="수정할 항목이 없습니다.")
    return trainer_service.update_notification_settings(
        db, _require_profile(db, trainer.id), fields
    )


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
        goals=profile.goals if profile is not None else "",
        **values,
    )


@router.get(
    "/trainer/clients/{member_id}/health-profile",
    response_model=MemberHealthProfileOut,
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
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(profile, field, value)
    db.commit()
    return _member_health_out(db, member_id)


@router.get("/trainer/clients/{member_id}/diet", response_model=list[ClientDietEntryOut])
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


@router.get("/trainer/clients/{member_id}/diet/photos/{photo_id}")
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


@router.get("/trainer/clients/{member_id}/history", response_model=list[RoutineHistoryOut])
def trainer_client_history(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[RoutineHistoryOut]:
    """담당 고객의 운동 완료 기록(최신순). 타 트레이너 기록/메모는 제외한다."""
    _require_client(db, trainer.id, member_id)
    return trainer_service.build_client_history(db, member_id, trainer.id)


@router.put(
    "/trainer/clients/{member_id}/history/{history_id}/feedback",
    response_model=RoutineHistoryOut,
)
def trainer_update_routine_feedback(
    member_id: str,
    history_id: str,
    payload: RoutineFeedbackRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> RoutineHistoryOut:
    """담당 회원의 배정 루틴 수행 기록에 피드백을 남기거나 고친다."""
    link = _require_client(db, trainer.id, member_id)
    if not link.active:
        raise HTTPException(status_code=404, detail="현재 담당 고객을 찾을 수 없습니다.")
    feedback = payload.feedback.strip()
    if not feedback:
        raise HTTPException(status_code=400, detail="피드백 내용이 필요합니다.")
    try:
        return trainer_service.update_assigned_routine_feedback(
            db, trainer.id, member_id, history_id, feedback
        )
    except trainer_service.RoutineNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.get(
    "/trainer/clients/{member_id}/diet-advice",
    response_model=DietAdviceResponse,
)
def trainer_client_diet_advice(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    period: Annotated[
        Literal["today", "week", "all"],
        Query(description="조언이 다룰 구간 — 회원 앱 기간 토글과 같은 이름"),
    ] = "today",
) -> DietAdviceResponse:
    """담당 고객의 기간별 식단 조언. 회원 앱과 **같은 문장**이다. (#1017)

    같은 회원의 같은 기간을 두 화면이 다르게 말하면, 상담에서 둘이 서로 다른
    이야기를 들고 앉게 된다.
    """
    _require_client(db, trainer.id, member_id)
    start, end = diet_service.period_bounds(period)
    days = diet_service.daily_totals(db, member_id, start, end)
    return DietAdviceResponse(
        period=period,
        from_date=start,
        to_date=end,
        days_logged=len(days),
        message=diet_service.period_coach_message(days, period),
    )


@router.get(
    "/trainer/clients/{member_id}/exercise-advice",
    response_model=ExerciseAdviceResponse,
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
    return ExerciseAdviceResponse(
        period=period,
        from_date=start,
        to_date=end,
        days_logged=len(days),
        message=exercise_service.period_coach_message(days, period),
    )


@router.get(
    "/trainer/clients/{member_id}/exercise-week",
    response_model=ExerciseWeekResponse,
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
    data = build_current_week(list(rows))
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


# ---- 채팅 (트레이너↔회원) ----

@router.get("/trainer/chat/unread", response_model=dict[str, int])
def trainer_chat_unread(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict[str, int]:
    """회원별 미확인 메시지 수(회원 발신·미읽음). 고객 목록 배지용."""
    return trainer_service.unread_counts_for_trainer(db, trainer.id)


@router.get("/trainer/clients/{member_id}/chat", response_model=list[ChatMessageOut])
def trainer_client_chat(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(50, ge=1, le=100, description="한 번에 가져올 최신 메시지 수"),
    before: str | None = Query(
        None, description="ISO datetime 커서 — 이전 페이지 요청(응답 created_at 사용)"
    ),
    before_id: str | None = Query(
        None, description="복합 커서 tie-break — 이전 페이지 가장 오래된 메시지의 id"
    ),
) -> list[ChatMessageOut]:
    """담당 고객과의 채팅 스레드(오래된→최신). 기본 최신 50건, (before, before_id)로 이전 페이지."""
    _require_client(db, trainer.id, member_id)
    before_dt: datetime | None = None
    if before:
        try:
            before_dt = datetime.fromisoformat(before)
        except ValueError as e:
            raise HTTPException(
                status_code=422, detail="before 는 ISO datetime 형식이어야 합니다."
            ) from e
    return trainer_service.build_chat_thread(
        db, trainer.id, member_id, limit=limit, before=before_dt, before_id=before_id
    )


@router.post("/trainer/clients/{member_id}/chat", response_model=ChatMessageOut, status_code=201)
def trainer_send_chat(
    member_id: str,
    payload: ChatSendRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ChatMessageOut:
    """트레이너가 담당 고객에게 메시지 발신."""
    _require_client(db, trainer.id, member_id)
    text = payload.text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="빈 메시지는 보낼 수 없습니다.")
    try:
        return trainer_service.send_message(
            db,
            trainer.id,
            member_id,
            "trainer",
            text,
            notify=notification_service.TRAINER_MESSAGE,
            client_request_id=payload.client_request_id,
        )
    except trainer_service.IdempotencyConflict as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post("/trainer/clients/{member_id}/chat/read")
def trainer_mark_chat_read(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """트레이너가 해당 고객 스레드를 읽음 처리."""
    _require_client(db, trainer.id, member_id)
    n = trainer_service.mark_thread_read(db, trainer.id, member_id, "trainer")
    return {"marked_read": n}


# ---- 루틴 배정 (트레이너/AI → 회원) ----

@router.get("/trainer/clients/{member_id}/routines", response_model=list[RoutineOut])
def trainer_client_routines(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[RoutineOut]:
    """담당 고객에게 배정된 루틴 목록."""
    _require_client(db, trainer.id, member_id)
    return trainer_service.build_routines(db, member_id, trainer.id)


@router.post("/trainer/clients/{member_id}/routines", response_model=RoutineOut, status_code=201)
def trainer_assign_routine(
    member_id: str,
    payload: RoutineAssignRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> RoutineOut:
    """담당 고객에게 루틴 배정(트레이너 직접 또는 AI 추천)."""
    _require_client(db, trainer.id, member_id)
    # type/source/길이·범위는 RoutineAssignRequest(Field/Literal)가 이미 422 로 거른다.
    # 공백만 있는 이름은 trim 후 400.
    if not payload.name.strip():
        raise HTTPException(status_code=400, detail="루틴 이름이 필요합니다.")
    return trainer_service.assign_routine(
        db, trainer.id, member_id,
        name=payload.name.strip(), minutes=payload.minutes,
        type_=payload.type, reason=payload.reason, source=payload.source,
        client_request_id=payload.client_request_id,
        exercise_date=payload.exercise_date,
        intensity=payload.intensity,
        sets=payload.sets,
        reps=payload.reps,
        weight=payload.weight,
    )


# ---- AI 개인운동 제안 검토 (#790) ----

@router.get(
    "/trainer/clients/{member_id}/routine-suggestions",
    response_model=list[RoutineOut],
)
def trainer_routine_suggestions(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[RoutineOut]:
    """검토를 기다리는 AI 개인운동 제안 목록.

    배정 목록(`GET .../routines`)과 나눠 둔다 — 배정은 이미 회원이 보는 것이고
    제안은 아직 아무에게도 닿지 않은 것이라, 한 목록에 섞이면 어느 쪽이 회원에게
    갔는지 알 수 없다.

    이 조회가 그날 후보를 준비한다(멱등). 준비된 후보는 승인 전까지 회원 조회에
    나타나지 않는다.
    """
    _require_client(db, trainer.id, member_id)
    return trainer_service.list_routine_suggestions(db, trainer.id, member_id)


@router.post(
    "/trainer/clients/{member_id}/routine-suggestions",
    response_model=RoutineOut,
    status_code=201,
)
def trainer_create_routine_suggestion(
    member_id: str,
    payload: RoutineSuggestionCreateRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> RoutineOut:
    """AI 개인운동 후보를 검토 대기로 등록한다. 회원에게는 아직 보이지 않는다."""
    _require_client(db, trainer.id, member_id)
    if not payload.name.strip():
        raise HTTPException(status_code=400, detail="운동 이름이 필요합니다.")
    return trainer_service.create_routine_suggestion(
        db,
        trainer.id,
        member_id,
        name=payload.name.strip(),
        minutes=payload.minutes,
        type_=payload.type,
        sets=payload.sets,
        reps=payload.reps,
        weight=payload.weight,
        reason=payload.reason,
        evidence=payload.evidence,
        client_request_id=payload.client_request_id,
    )


@router.post(
    "/trainer/routine-suggestions/{suggestion_id}/approve",
    response_model=RoutineOut,
)
def trainer_approve_routine_suggestion(
    suggestion_id: str,
    payload: RoutineSuggestionApproveRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> RoutineOut:
    """제안을 승인해 회원에게 배정한다. 준 필드가 있으면 고쳐서 승인한다."""
    fields = payload.model_dump(exclude_unset=True)
    name = fields.get("name")
    if name is not None and not name.strip():
        raise HTTPException(status_code=400, detail="운동 이름이 필요합니다.")
    try:
        return trainer_service.approve_routine_suggestion(
            db,
            trainer.id,
            suggestion_id,
            name=name.strip() if name is not None else None,
            minutes=fields.get("minutes"),
            type_=fields.get("type"),
            sets=fields.get("sets"),
            reps=fields.get("reps"),
            weight=fields.get("weight"),
            reason=fields.get("reason"),
        )
    except trainer_service.RoutineNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_service.RoutineAlreadyReviewed as exc:
        # 두 번 눌렀거나 다른 창에서 이미 처리한 경우다. 404 로 뭉개면 트레이너가
        # "사라졌다" 로 읽는데, 실제로는 이미 반영돼 있다.
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post(
    "/trainer/routine-suggestions/{suggestion_id}/dismiss",
    response_model=RoutineOut,
)
def trainer_dismiss_routine_suggestion(
    suggestion_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> RoutineOut:
    """제안을 추천하지 않기로 한다. 회원 배정도 알림도 만들지 않는다."""
    try:
        return trainer_service.dismiss_routine_suggestion(
            db, trainer.id, suggestion_id
        )
    except trainer_service.RoutineNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_service.RoutineAlreadyReviewed as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post(
    "/trainer/clients/{member_id}/program",
    response_model=list[RoutineOut],
    status_code=201,
)
def trainer_assign_program(
    member_id: str,
    payload: ProgramAssignRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[RoutineOut]:
    """다중 세션 프로그램을 담당 고객에게 배정한다. 세션 하나가 루틴 한 건. (#709)

    세션이 하나뿐이면 결과가 단일 배정(`POST .../routines`)과 같은 모양이라,
    회원 화면에 없던 세션 라벨이 생기지 않는다. `client_request_id` 는 프로그램
    전체에 대해 멱등하다.
    """
    _require_client(db, trainer.id, member_id)
    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="프로그램 이름이 필요합니다.")
    if not any(session.exercises for session in payload.sessions):
        # 운동이 하나도 없는 프로그램을 배정하면 회원에게 빈 루틴만 간다.
        raise HTTPException(status_code=400, detail="운동이 하나 이상 필요합니다.")
    return trainer_service.assign_program(
        db, trainer.id, member_id,
        name=name,
        sessions=payload.sessions,
        client_request_id=payload.client_request_id,
    )


@router.put(
    "/trainer/clients/{member_id}/routines/{routine_id}",
    response_model=RoutineOut,
)
def trainer_update_routine(
    member_id: str,
    routine_id: str,
    payload: RoutineUpdateRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> RoutineOut:
    """배정한 루틴 수정(부분). 이름·시간·종류·사유만 바뀐다. (#504)

    남의 배정과 없는 루틴은 똑같이 404 다 — 존재 여부를 드러내지 않는다.
    """
    _require_client(db, trainer.id, member_id)
    fields = payload.model_dump(exclude_unset=True)
    if not fields:
        # 빈 PUT 을 성공으로 처리하면 클라이언트가 저장됐다고 오해한다.
        raise HTTPException(status_code=400, detail="수정할 항목이 없습니다.")
    if "name" in fields and not fields["name"].strip():
        raise HTTPException(status_code=400, detail="루틴 이름이 필요합니다.")
    if "name" in fields:
        fields["name"] = fields["name"].strip()
    try:
        return trainer_service.update_routine(
            db, trainer.id, member_id, routine_id, fields
        )
    except trainer_service.RoutineNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.delete("/trainer/clients/{member_id}/routines/{routine_id}")
def trainer_delete_routine(
    member_id: str,
    routine_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """배정한 루틴 철회. 회원 앱에서도 사라진다. (#504)"""
    _require_client(db, trainer.id, member_id)
    try:
        trainer_service.delete_routine(db, trainer.id, member_id, routine_id)
    except trainer_service.RoutineNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"status": "deleted"}


# ---- 회원별 트레이너 메모 (#706) ----
#
# 회원 상세의 '메모'와 채팅 인사이트 저장이 같은 목록을 쓴다. 모든 경로가
# `_require_client` 를 지나므로 담당 관계가 없는 트레이너는 남의 회원 메모를
# 조회·수정·삭제할 수 없다(없는 회원과 똑같이 404).

@router.get("/trainer/clients/{member_id}/memos", response_model=list[TrainerMemoOut])
def trainer_client_memos(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[TrainerMemoOut]:
    """담당 고객에 대해 내가 남긴 메모 목록(최신 먼저)."""
    _require_client(db, trainer.id, member_id)
    return trainer_service.build_memos(db, trainer.id, member_id)


@router.post(
    "/trainer/clients/{member_id}/memos",
    response_model=TrainerMemoOut,
    status_code=201,
)
def trainer_create_memo(
    member_id: str,
    payload: TrainerMemoCreateRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerMemoOut:
    """담당 고객에 대한 메모 작성.

    `insight_id` 를 보내면 그 채팅 인사이트에 대해 멱등이라 같은 신호를 반복
    저장해도 메모가 늘지 않는다(201 로 기존 메모가 그대로 돌아온다).
    """
    _require_client(db, trainer.id, member_id)
    body = payload.body.strip()
    if not body:
        # 공백만 있는 메모를 성공으로 처리하면 목록에 빈 줄이 쌓인다.
        raise HTTPException(status_code=400, detail="메모 내용이 필요합니다.")
    return trainer_service.create_memo(
        db, trainer.id, member_id,
        body=body,
        source=payload.source,
        insight_id=payload.insight_id,
        insight_kind=payload.insight_kind,
    )


@router.put(
    "/trainer/clients/{member_id}/memos/{memo_id}",
    response_model=TrainerMemoOut,
)
def trainer_update_memo(
    member_id: str,
    memo_id: str,
    payload: TrainerMemoUpdateRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerMemoOut:
    """메모 수정(부분). 본문만 바뀐다."""
    _require_client(db, trainer.id, member_id)
    fields = payload.model_dump(exclude_unset=True)
    if not fields:
        raise HTTPException(status_code=400, detail="수정할 항목이 없습니다.")
    if "body" in fields:
        fields["body"] = fields["body"].strip()
        if not fields["body"]:
            raise HTTPException(status_code=400, detail="메모 내용이 필요합니다.")
    try:
        return trainer_service.update_memo(
            db, trainer.id, member_id, memo_id, fields
        )
    except trainer_service.MemoNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.delete("/trainer/clients/{member_id}/memos/{memo_id}")
def trainer_delete_memo(
    member_id: str,
    memo_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """메모 삭제. 트레이너 혼자 보는 기록이라 비활성 상태를 두지 않고 지운다."""
    _require_client(db, trainer.id, member_id)
    try:
        trainer_service.delete_memo(db, trainer.id, member_id, memo_id)
    except trainer_service.MemoNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"status": "deleted"}


# ---- 고객 후속 관리 할 일 (#869) ----
#
# 고객별 등록·조회는 `_require_client` 를 지나므로 담당 관계가 없는 트레이너는
# 남의 고객에게 할 일을 남길 수 없다(없는 회원과 똑같이 404). 등록 뒤의 조회·수정·
# 완료는 트레이너 소유권만 보면 된다 — 담당이 해제돼도 이미 남긴 업무는 내 것이고,
# 여기서 담당을 다시 요구하면 해제된 고객의 할 일이 목록에 남은 채 지울 수 없게 된다.

@router.get(
    "/trainer/clients/{member_id}/follow-ups",
    response_model=list[TrainerFollowUpTaskOut],
)
def trainer_client_follow_ups(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    include_completed: Annotated[bool, Query()] = False,
) -> list[TrainerFollowUpTaskOut]:
    """담당 고객에 대해 내가 남긴 후속 관리 할 일(예정일 순).

    기본은 미완료만이다. 완료 이력까지 보려면 `include_completed=true`.
    """
    _require_client(db, trainer.id, member_id)
    return trainer_service.build_client_follow_ups(
        db, trainer.id, member_id, include_completed=include_completed
    )


@router.post(
    "/trainer/clients/{member_id}/follow-ups",
    response_model=TrainerFollowUpTaskOut,
    status_code=201,
)
def trainer_create_follow_up(
    member_id: str,
    payload: TrainerFollowUpTaskCreateRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerFollowUpTaskOut:
    """담당 고객에 대한 후속 관리 할 일 등록.

    `client_request_id` 를 보내면 그 시도에 대해 멱등이라, 응답을 못 받고 재시도해도
    같은 할 일이 두 번 생기지 않는다(201 로 먼저 저장된 할 일이 돌아온다).
    """
    _require_client(db, trainer.id, member_id)
    title = payload.title.strip()
    if not title:
        # 공백만 있는 할 일을 성공으로 처리하면 대시보드에 빈 줄이 쌓인다.
        raise HTTPException(status_code=400, detail="할 일 내용이 필요합니다.")
    return trainer_service.create_follow_up(
        db,
        trainer.id,
        member_id,
        title=title,
        due_date=payload.due_date,
        context_type=payload.context_type,
        client_request_id=payload.client_request_id,
    )


@router.get("/trainer/follow-ups", response_model=list[TrainerFollowUpTaskOut])
def trainer_follow_ups(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    scope: Annotated[FollowUpScope, Query()] = "due",
) -> list[TrainerFollowUpTaskOut]:
    """내 후속 관리 할 일(예정일 순, 지난 항목이 앞).

    `scope=due` 는 대시보드가 읽는 범위다 — 오늘 예정과 기한이 지난 미완료.
    `scope=open` 은 예정일과 무관한 미완료 전체.
    """
    if scope == "open":
        return trainer_service.build_open_follow_ups(db, trainer.id)
    return trainer_service.build_due_follow_ups(db, trainer.id)


@router.put("/trainer/follow-ups/{task_id}", response_model=TrainerFollowUpTaskOut)
def trainer_update_follow_up(
    task_id: str,
    payload: TrainerFollowUpTaskUpdateRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerFollowUpTaskOut:
    """할 일 수정(부분). 내용과 예정일만 바뀐다."""
    fields = payload.model_dump(exclude_unset=True)
    if not fields:
        raise HTTPException(status_code=400, detail="수정할 항목이 없습니다.")
    if "title" in fields:
        fields["title"] = fields["title"].strip()
        if not fields["title"]:
            raise HTTPException(status_code=400, detail="할 일 내용이 필요합니다.")
    try:
        return trainer_service.update_follow_up(db, trainer.id, task_id, fields)
    except trainer_service.FollowUpTaskNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.post(
    "/trainer/follow-ups/{task_id}/complete",
    response_model=TrainerFollowUpTaskOut,
)
def trainer_complete_follow_up(
    task_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerFollowUpTaskOut:
    """할 일 완료 처리. 같은 요청을 반복해도 성공하고 완료 시각은 유지된다."""
    try:
        return trainer_service.complete_follow_up(db, trainer.id, task_id)
    except trainer_service.FollowUpTaskNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


# ---- 프로그램 초안 (#708) ----
#
# 초안은 트레이너의 것이라 회원 경로 아래가 아니다. 소유권 경계는 trainer_id 이고,
# 남의 초안과 없는 초안은 똑같이 404 다.

@router.get("/trainer/programs", response_model=list[TrainerProgramDraftSummary])
def trainer_program_drafts(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[TrainerProgramDraftSummary]:
    """내가 저장한 프로그램 초안 목록(최근 수정 먼저, 운동 구성 제외)."""
    return trainer_service.build_program_drafts(db, trainer.id)


@router.post(
    "/trainer/programs",
    response_model=TrainerProgramDraftOut,
    status_code=201,
)
def trainer_create_program_draft(
    payload: TrainerProgramDraftCreate,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerProgramDraftOut:
    """프로그램 초안 저장. 세션이 여러 개여도, 비어 있어도 저장된다."""
    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="프로그램 이름이 필요합니다.")
    return trainer_service.create_program_draft(
        db, trainer.id,
        name=name,
        goal=payload.goal.strip(),
        period=payload.period.strip(),
        memo=payload.memo,
        sessions=payload.sessions,
    )


@router.get(
    "/trainer/programs/{draft_id}",
    response_model=TrainerProgramDraftOut,
)
def trainer_program_draft(
    draft_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerProgramDraftOut:
    """저장된 초안 상세 — 편집기로 불러올 때 쓴다."""
    try:
        return trainer_service.get_program_draft(db, trainer.id, draft_id)
    except trainer_service.ProgramDraftNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.put(
    "/trainer/programs/{draft_id}",
    response_model=TrainerProgramDraftOut,
)
def trainer_update_program_draft(
    draft_id: str,
    payload: TrainerProgramDraftUpdate,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerProgramDraftOut:
    """저장된 초안 수정(부분). `sessions` 는 통째로 교체된다."""
    fields = payload.model_dump(exclude_unset=True)
    if not fields:
        raise HTTPException(status_code=400, detail="수정할 항목이 없습니다.")
    for text_field in ("name", "goal", "period"):
        if text_field in fields:
            fields[text_field] = fields[text_field].strip()
    if "name" in fields and not fields["name"]:
        raise HTTPException(status_code=400, detail="프로그램 이름이 필요합니다.")
    try:
        return trainer_service.update_program_draft(
            db, trainer.id, draft_id, fields
        )
    except trainer_service.ProgramDraftNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.delete("/trainer/programs/{draft_id}")
def trainer_delete_program_draft(
    draft_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """저장된 초안 삭제. 이미 배정한 루틴·등록한 일정은 그대로 남는다."""
    try:
        trainer_service.delete_program_draft(db, trainer.id, draft_id)
    except trainer_service.ProgramDraftNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"status": "deleted"}


@router.post(
    "/trainer/clients/{member_id}/routine-options",
    response_model=RoutineOptionsOut,
    # LLM 을 부르는 엔드포인트라 /ai-coach/chat 과 같은 가드를 건다. 생성이
    # 실패해 규칙형으로 폴백해도 공급자 호출 비용은 이미 나간 뒤이므로,
    # 연타가 그대로 청구되지 않게 앞에서 막는다.
    dependencies=[
        Depends(
            rate_limit("routine-options", get_settings().routine_options_per_minute)
        )
    ],
)
def trainer_routine_options(
    member_id: str,
    payload: RoutineOptionsRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> RoutineOptionsOut:
    """회원 실데이터를 LLM에 전달해 두 개의 맞춤 루틴 후보를 생성한다.

    설정된 AI 공급자를 사용할 수 없거나 응답 계약이 잘못되면 동일 응답 형태의
    규칙 기반 후보로 폴백한다.
    """
    _require_client(db, trainer.id, member_id)
    return trainer_routine_options_service.generate_routine_options(
        db,
        trainer.id,
        member_id,
        payload,
    )


@router.get(
    "/trainer/dashboard/coaching-summary",
    response_model=DashboardCoachingSummaryOut,
)
def trainer_dashboard_coaching_summary(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> DashboardCoachingSummaryOut:
    """식단·운동·건강 프로필·최근 대화를 합친 오늘의 고객별 코칭 요약."""
    settings = get_settings()
    if settings.rate_limit_enabled:
        # 인증된 트레이너 단위로 비용 버킷을 분리해 같은 헬스장/NAT의 사용자가
        # 서로 한도를 소진하지 않게 한다. 운영의 공유 저장소 전환 전까지는 기존
        # RateLimiter 인터페이스를 유지한다.
        limiter.check(
            f"dashboard-coaching-summary:trainer:{trainer.id}",
            settings.routine_options_per_minute,
            60.0,
        )
    return trainer_dashboard_coaching_service.generate_summary(db, trainer.id)


# ---- 스케줄 (트레이너 타임라인 + 예약→수업→기록 완료 루프) ----

@router.get("/trainer/schedule/booked-dates", response_model=list[str])
def trainer_booked_dates(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[str]:
    """예약이 있는(공백 아닌) 날짜 목록 — 주간 스트립 도트용."""
    return trainer_service.booked_dates(db, trainer.id)


@router.get("/trainer/schedule", response_model=list[ScheduleSessionOut])
def trainer_schedule(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    date: str | None = Query(None, description="YYYY-MM-DD (기본: 오늘)"),
    from_: str | None = Query(
        None, alias="from", description="구간 시작 YYYY-MM-DD (to 와 함께)"
    ),
    to: str | None = Query(None, description="구간 끝 YYYY-MM-DD (from 과 함께)"),
    member_id: str | None = Query(None, description="담당 고객의 세션만"),
) -> list[ScheduleSessionOut]:
    """타임라인. 기본은 하루(`date`), `from`/`to` 를 주면 그 구간 전체.

    주 캘린더가 7일치를 한 번에 읽기 위해 구간 조회를 지원한다 — 하루짜리
    요청을 요일마다 반복하면 요청이 7배가 된다.

    `member_id` 만 주면 날짜 제한 없이 그 고객의 전체 세션을 준다. 고객
    상세의 루틴 이력이 필요로 하는 것이고, 구간으로 흉내내면 그 구간보다
    오래된 기록이 조용히 사라진다.
    """
    if member_id is not None:
        _require_client(db, trainer.id, member_id)

    if from_ is not None or to is not None:
        # 한쪽만 오면 어느 구간인지 알 수 없다 — 조용히 하루로 떨어뜨리면
        # 클라이언트는 구간을 받았다고 믿는다.
        if from_ is None or to is None:
            raise HTTPException(
                status_code=422, detail="from 과 to 는 함께 지정해야 합니다."
            )
        if not _is_ymd(from_) or not _is_ymd(to):
            raise HTTPException(
                status_code=422, detail="from/to 는 YYYY-MM-DD 형식이어야 합니다."
            )
        if from_ > to:
            raise HTTPException(status_code=422, detail="from 은 to 보다 늦을 수 없습니다.")
        return trainer_service.build_schedule_range(
            db, trainer.id, from_, to, member_id=member_id
        )

    if member_id is not None and date is None:
        return trainer_service.build_client_schedule(db, trainer.id, member_id)

    day = date or trainer_service.today_iso()
    if not _is_ymd(day):
        raise HTTPException(status_code=422, detail="date 는 YYYY-MM-DD 형식이어야 합니다.")
    return trainer_service.build_schedule_range(
        db, trainer.id, day, day, member_id=member_id
    )


@router.post("/trainer/schedule", response_model=ScheduleSessionOut, status_code=201)
def trainer_create_session(
    payload: ScheduleCreateRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ScheduleSessionOut:
    """예약 추가(status 예정). member_id 를 주면 담당 고객이어야 한다(아니면 404)."""
    if payload.member_id:
        _require_client(db, trainer.id, payload.member_id)
    try:
        return trainer_service.create_session(
            db,
            trainer.id,
            date=payload.date,
            time=payload.time,
            client_name=payload.client_name,
            member_id=payload.member_id,
            type_=payload.type,
            duration_minutes=payload.duration_minutes,
            note=payload.note,
            program=payload.program,
            client_request_id=payload.client_request_id,
        )
    except trainer_service.IdempotencyConflict as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post(
    "/trainer/schedule/recurring/preview",
    response_model=ScheduleRecurringPreviewOut,
)
def trainer_preview_recurring_sessions(
    payload: ScheduleRecurringRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ScheduleRecurringPreviewOut:
    """반복 설정이 만들 회차와, 그 자리에 이미 있는 일정. (#870)

    저장 전에 보여 주기 위한 경로다 — 반복은 한 번에 여러 건을 만들고, 요일이나
    종료일을 잘못 골랐을 때 되돌리는 비용이 한 건씩 지우는 일이다.
    """
    if payload.member_id:
        _require_client(db, trainer.id, payload.member_id)
    dates, conflicts = trainer_service.preview_recurring_sessions(
        db,
        trainer.id,
        start=payload.date,
        time=payload.time,
        weekdays=payload.weekdays,
        count=payload.count,
        until=payload.until,
    )
    return ScheduleRecurringPreviewOut(dates=dates, conflicts=conflicts)


@router.post(
    "/trainer/schedule/recurring",
    response_model=list[ScheduleSessionOut],
    status_code=201,
)
def trainer_create_recurring_sessions(
    payload: ScheduleRecurringRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[ScheduleSessionOut]:
    """주간 반복으로 PT 회차를 한 번에 등록한다. (#870)

    전부 만들거나 하나도 만들지 않는다 — 겹치는 회차가 있으면 409 로 멈추고, 응답
    본문에 겹친 세션을 실어 화면이 어느 주가 문제인지 짚어 줄 수 있게 한다.
    """
    if payload.member_id:
        _require_client(db, trainer.id, payload.member_id)
    try:
        return trainer_service.create_recurring_sessions(
            db,
            trainer.id,
            start=payload.date,
            time=payload.time,
            weekdays=payload.weekdays,
            client_name=payload.client_name,
            member_id=payload.member_id,
            type_=payload.type,
            duration_minutes=payload.duration_minutes,
            note=payload.note,
            count=payload.count,
            until=payload.until,
            client_request_id=payload.client_request_id,
        )
    except trainer_service.ScheduleSeriesConflict as exc:
        raise HTTPException(
            status_code=409,
            detail={
                "message": str(exc),
                "conflicts": [
                    conflict.model_dump(mode="json") for conflict in exc.conflicts
                ],
            },
        ) from exc
    except trainer_service.ScheduleError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.put(
    "/trainer/clients/{member_id}/schedule-program",
    response_model=ScheduleProgramRegisterOut,
)
def trainer_register_schedule_program(
    member_id: str,
    payload: ScheduleProgramRegisterRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ScheduleProgramRegisterOut:
    """Atomically attach an AI program or create the member's PT session."""
    result = trainer_service.register_program(
        db,
        trainer.id,
        member_id,
        date=payload.date,
        time=payload.time,
        duration_minutes=payload.duration_minutes,
        client_name=payload.client_name,
        program=payload.program,
    )
    if result is None:
        raise HTTPException(status_code=404, detail="담당 고객을 찾을 수 없습니다.")
    session, attached_to_existing = result
    return ScheduleProgramRegisterOut(
        session=session,
        attached_to_existing=attached_to_existing,
    )


@router.put("/trainer/schedule/{session_id}", response_model=ScheduleSessionOut)
def trainer_update_session(
    session_id: str,
    payload: ScheduleUpdateRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ScheduleSessionOut:
    """예약 수정(제공된 필드만). member_id 변경 시 담당 고객이어야 한다.
    완료된 세션은 기록과의 정합성을 위해 수정 불가(409)."""
    fields = payload.model_dump(exclude_unset=True)
    if fields.get("member_id"):
        _require_client(db, trainer.id, fields["member_id"])
    try:
        out = trainer_service.update_session(db, trainer.id, session_id, fields)
    except trainer_service.ScheduleConflict as e:
        raise HTTPException(status_code=409, detail=str(e)) from e
    if out is None:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없습니다.")
    return out


@router.delete("/trainer/schedule/{session_id}")
def trainer_delete_session(
    session_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """예약 삭제."""
    try:
        deleted = trainer_service.delete_session(db, trainer.id, session_id)
    except trainer_service.ScheduleConflict as e:
        raise HTTPException(status_code=409, detail=str(e)) from e
    if not deleted:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없습니다.")
    return {"status": "deleted"}


@router.post("/trainer/schedule/{session_id}/complete", response_model=ScheduleSessionOut)
def trainer_complete_session(
    session_id: str,
    payload: ScheduleCompleteRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ScheduleSessionOut:
    """세션 완료(예정→완료). 매칭된 회원이 있으면 운동기록으로 적재.

    취소·노쇼로 이미 마무리된 세션은 409 다 — 하지 않은 PT 를 완료로 되돌리면
    회원 운동 기록으로 적재된다(#871).
    """
    try:
        out = trainer_service.complete_session(db, trainer.id, session_id, payload.note)
    except trainer_service.ScheduleError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except trainer_service.ScheduleConflict as e:
        raise HTTPException(status_code=409, detail=str(e)) from e
    if out is None:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없습니다.")
    return out


@router.post("/trainer/schedule/{session_id}/cancel", response_model=ScheduleSessionOut)
def trainer_cancel_session(
    session_id: str,
    payload: ScheduleCancelRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ScheduleSessionOut:
    """세션 취소(예정→취소). 일정을 지우지 않고 기록으로 남긴다. (#871)

    삭제(`DELETE`)와 다른 동작이다 — 삭제는 잘못 만든 일정을 없애는 일이고,
    이 경로는 실제로 있었던 약속이 진행되지 않았다는 사실을 남긴다. 같은 요청을
    반복해도 200 이고 취소 시각·주체는 처음 값을 지킨다.
    """
    try:
        out = trainer_service.cancel_session(
            db,
            trainer.id,
            session_id,
            source=payload.source,
            reason=payload.reason.strip(),
        )
    except trainer_service.ScheduleError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except trainer_service.ScheduleConflict as e:
        raise HTTPException(status_code=409, detail=str(e)) from e
    if out is None:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없습니다.")
    return out


@router.post("/trainer/schedule/{session_id}/reopen", response_model=ScheduleSessionOut)
def trainer_reopen_session(
    session_id: str,
    payload: ScheduleReopenRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ScheduleSessionOut:
    """완료 세션을 미래 날짜의 예정으로 되돌린다(예정→완료의 역방향). (#1396)

    일정 수정 화면에서 완료된 회차의 날짜를 앞으로 옮길 때만 쓰는 경로다 —
    완료 시 적재된 파생 기록(트레이너 이력·회원 운동기록)을 함께 지운다.
    """
    try:
        out = trainer_service.reopen_session(
            db, trainer.id, session_id, new_date=payload.date
        )
    except trainer_service.ScheduleConflict as e:
        raise HTTPException(status_code=409, detail=str(e)) from e
    if out is None:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없습니다.")
    return out


@router.post("/trainer/schedule/{session_id}/no-show", response_model=ScheduleSessionOut)
def trainer_mark_session_no_show(
    session_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ScheduleSessionOut:
    """세션 노쇼(예정→노쇼). 예약된 시간에 회원이 오지 않았다는 기록. (#871)

    취소와 나누는 까닭은 두 일이 다르기 때문이다 — 취소는 진행 전에 약속이
    거두어진 것이고, 노쇼는 약속이 그대로 있는데 회원이 오지 않은 것이다.
    """
    try:
        out = trainer_service.mark_session_no_show(db, trainer.id, session_id)
    except trainer_service.ScheduleError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except trainer_service.ScheduleConflict as e:
        raise HTTPException(status_code=409, detail=str(e)) from e
    if out is None:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없습니다.")
    return out


@router.post(
    "/trainer/schedule/{session_id}/program/send",
    response_model=ScheduleSessionOut,
)
def trainer_send_session_program(
    session_id: str,
    payload: ScheduleProgramSendRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ScheduleSessionOut:
    """완료한 세션의 프로그램을 그 회원에게 보낸다. (#822)

    수업을 마친 뒤 오늘 한 것을 회원 앱으로 넘기는 마지막 한 걸음이다. 배정
    자체는 코칭 탭의 프로그램 배정과 같은 경로를 타므로, 회원은 출처와 무관하게
    같은 모양의 루틴을 받는다. 같은 세션을 두 번 눌러도 배정은 한 번이다.
    """
    try:
        out = trainer_service.send_session_program(
            db, trainer.id, session_id,
            client_request_id=payload.client_request_id,
        )
    except trainer_service.ScheduleError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    if out is None:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없습니다.")
    return out


# ---- AI 코칭 (담당 고객 데이터 기반) ----

@router.post("/trainer/clients/{member_id}/ai-coach", response_model=ClientCoachOut)
def trainer_client_ai_coach(
    member_id: str,
    payload: ClientCoachRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ClientCoachOut:
    """담당 고객의 데이터를 근거로 AI에게 코칭을 묻는다.

    회원 앱의 `/ai-coach/chat` 과 같은 RAG 파이프라인이지만, 검색 스코프가
    호출자(트레이너)가 아니라 **담당 회원**이다 — 트레이너가 자기 자신의 (비어
    있는) 기록으로 코칭받는 일이 없도록. 담당 링크 확인이 접근 경계이며,
    남의 고객이면 404 로 존재조차 드러내지 않는다.
    """
    _require_client(db, trainer.id, member_id)
    message = payload.message.strip()
    if not message:
        raise HTTPException(status_code=400, detail="메시지가 비어 있습니다.")

    # 이 트레이너 전용 스레드다(#588). 검색 스코프는 회원이지만 문답의 주인은
    # 트레이너라, 회원 대화(trainer_id IS NULL)와 섞이면 회원이 앱을 열었을 때
    # 자기가 하지 않은 대화를 보게 된다.
    history = conversation.load_messages(db, member_id, trainer_id=trainer.id)
    reply, sources = coach_answer(db, member_id, message, history)
    conversation.append_exchange(
        db, member_id, question=message, reply=reply, sources=sources,
        trainer_id=trainer.id,
    )
    return ClientCoachOut(member_id=member_id, reply=reply, sources=sources)


@router.get(
    "/trainer/clients/{member_id}/ai-coach",
    response_model=list[ClientCoachMessageOut],
)
def trainer_client_ai_coach_history(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[ClientCoachMessageOut]:
    """이 트레이너가 해당 고객에 대해 나눈 문답 복원(오래된→최신).

    시트를 닫았다 열면 대화가 사라지던 문제를 없앤다. 다른 트레이너의 문답은
    스레드가 달라 보이지 않는다.
    """
    _require_client(db, trainer.id, member_id)
    rows = conversation.load_messages(db, member_id, trainer_id=trainer.id)
    return [
        ClientCoachMessageOut(
            role=m.role,
            content=m.content,
            sources=conversation.parse_sources(m.sources_json),
        )
        for m in rows
    ]


# ---- 주간 리포트 (트레이너 → 회원) ----

def _report_week(day: str) -> _date:
    """리포트 주차를 검증해 그 주의 월요일로 정규화한다.

    아직 오지 않은 주는 거부한다 — 값이 전부 0 인 리포트를 만들어 회원에게
    보낼 수 있고, 화면에도 다음 주로 가는 길이 없다.
    """
    if not _is_ymd(day):
        raise HTTPException(status_code=422, detail="week_start 는 YYYY-MM-DD 형식이어야 합니다.")
    week = trainer_service.week_start_of(_date.fromisoformat(day))
    today = _date.fromisoformat(trainer_service.today_iso())
    if week > trainer_service.week_start_of(today):
        raise HTTPException(status_code=422, detail="아직 오지 않은 주는 조회할 수 없습니다.")
    return week


@router.get("/trainer/clients/{member_id}/report", response_model=WeeklyReportOut)
def trainer_client_report(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    week_start: str | None = Query(None, description="YYYY-MM-DD (기본: 이번 주)"),
) -> WeeklyReportOut:
    """담당 고객의 주간 리포트. 아무 요일을 줘도 그 주의 월요일로 정규화한다."""
    _require_client(db, trainer.id, member_id)
    return trainer_service.build_weekly_report(
        db, trainer.id, member_id, _report_week(week_start or trainer_service.today_iso())
    )


@router.get(
    "/trainer/clients/{member_id}/report/summary",
    response_model=ReportSummaryOut,
)
def trainer_client_report_summary(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    week_start: str | None = Query(None, description="YYYY-MM-DD (기본: 이번 주)"),
) -> ReportSummaryOut:
    """그 주의 리포트 요약.

    리포트 본문과 **따로** 부른다. 생성에 몇 초가 걸리는데 한 응답에 묶으면
    고객을 고를 때마다 화면 전체가 그만큼 멈춘다.
    """
    _require_client(db, trainer.id, member_id)
    settings = get_settings()
    if settings.rate_limit_enabled:
        # 트레이너 단위로 비용 버킷을 나눈다 — 같은 헬스장의 다른 트레이너가
        # 한도를 대신 소진하지 않게.
        limiter.check(
            f"report-summary:trainer:{trainer.id}",
            settings.routine_options_per_minute,
            60.0,
        )
    return trainer_report_summary_service.generate_summary(
        db, trainer.id, member_id, _report_week(week_start or trainer_service.today_iso())
    )


@router.get(
    "/trainer/clients/{member_id}/report/feedback",
    response_model=ReportFeedbackOut,
)
def trainer_client_report_feedback(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    week_start: str | None = Query(None, description="YYYY-MM-DD (기본: 이번 주)"),
) -> ReportFeedbackOut:
    """그 주 리포트에 저장해 둔 피드백 초안. (#821)

    저장한 적이 없으면 빈 본문으로 답한다 — 초안이 없는 것은 오류가 아니라
    아직 쓰지 않은 상태이고, 화면은 그때 자동 생성 문구를 쓴다.
    """
    _require_client(db, trainer.id, member_id)
    return trainer_service.get_report_feedback(
        db, trainer.id, member_id,
        _report_week(week_start or trainer_service.today_iso()),
    )


@router.put(
    "/trainer/clients/{member_id}/report/feedback",
    response_model=ReportFeedbackOut,
)
def trainer_save_client_report_feedback(
    member_id: str,
    payload: ReportFeedbackSaveRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ReportFeedbackOut:
    """피드백 초안을 저장한다. 같은 주에 다시 저장하면 덮어쓴다. (#821)

    PUT 인 까닭: 입력창의 현재 문구로 그 주의 초안을 통째로 바꾸는 동작이라
    여러 번 눌러도 결과가 같다. 전송(`/report/send`)과는 별개다 — 저장은
    회원에게 아무것도 보내지 않는다.
    """
    _require_client(db, trainer.id, member_id)
    week = _report_week(payload.week_start or trainer_service.today_iso())
    return trainer_service.save_report_feedback(
        db, trainer.id, member_id, week, payload.body
    )


@router.post(
    "/trainer/clients/{member_id}/report/send",
    response_model=ChatMessageOut,
    status_code=201,
)
def trainer_send_report(
    member_id: str,
    payload: ReportSendRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ChatMessageOut:
    """리포트를 회원의 채팅 스레드로 보낸다.

    별도 리포트 함을 만들지 않는 이유: 회원이 이미 읽고 있는 대화에 도착해야
    실제로 읽힌다. 본문을 직접 주면 트레이너가 손본 버전이 나가고, 없으면
    서버가 생성한 것이 나간다.
    """
    _require_client(db, trainer.id, member_id)
    week = _report_week(payload.week_start or trainer_service.today_iso())
    text = (payload.message or "").strip()
    if not text:
        report = trainer_service.build_weekly_report(db, trainer.id, member_id, week)
        text = report.message
    return trainer_service.send_message(
        db, trainer.id, member_id, "trainer", text,
        notify=notification_service.WEEKLY_REPORT,
        report_week_start=week.isoformat(),
    )


@router.post(
    "/trainer/clients/{member_id}/report/send-pdf",
    response_model=ChatMessageOut,
    status_code=201,
)
async def trainer_send_report_pdf(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    pdf: UploadFile = File(...),
    week_start: str = Form(...),
    message: str = Form("이번 주 리포트입니다."),
    client_request_id: str | None = Form(None, min_length=1, max_length=64),
) -> ChatMessageOut:
    """현재 리포트에서 생성한 PDF만 담당 고객 채팅으로 전송한다."""
    link = _require_client(db, trainer.id, member_id)
    if not link.active:
        raise HTTPException(status_code=404, detail="담당 고객을 찾을 수 없습니다.")
    week = _report_week(week_start)
    text = message.strip() or "이번 주 리포트입니다."

    # 재시도는 기존 메시지를 바로 돌려줘 파일을 다시 쓰지 않는다.
    if client_request_id:
        existing = trainer_service.find_message_by_client_request(
            db, trainer.id, member_id, "trainer", client_request_id
        )
        if existing is not None:
            if existing.body != text or existing.attachment_type != "pdf":
                raise HTTPException(
                    status_code=409,
                    detail="같은 client_request_id에 다른 메시지를 보낼 수 없습니다.",
                )
            return trainer_service.chat_message_out(existing, "trainer")

    if pdf.content_type != "application/pdf":
        raise HTTPException(status_code=415, detail="PDF 파일만 전송할 수 있습니다.")
    settings = get_settings()
    data = await pdf.read(settings.max_report_pdf_bytes + 1)
    if len(data) > settings.max_report_pdf_bytes:
        raise HTTPException(status_code=413, detail="PDF 파일 용량이 너무 큽니다.")
    if not data.startswith(b"%PDF-") or b"%%EOF" not in data[-1024:]:
        raise HTTPException(status_code=415, detail="유효한 PDF 파일이 아닙니다.")

    display_name = re.sub(
        r"[\x00-\x1f]", "_", PurePath(pdf.filename or "weekly-report.pdf").name
    )
    if not display_name.lower().endswith(".pdf"):
        display_name = "weekly-report.pdf"
    # DB 컬럼 길이를 넘는 사용자 filename이 메시지 저장을 깨지 않게 한다.
    if len(display_name) > 255:
        display_name = f"{display_name[:-4][:251]}.pdf"
    file_id: str | None = None
    try:
        file_id = report_pdf_storage.save(data)
        sent = trainer_service.send_message(
            db,
            trainer.id,
            member_id,
            "trainer",
            text,
            notify=notification_service.WEEKLY_REPORT,
            client_request_id=client_request_id,
            attachment_file_name=display_name,
            attachment_file_id=file_id,
            attachment_file_size=len(data),
            report_week_start=week.isoformat(),
        )
        # 동시 재시도 두 건이 모두 사전 조회를 통과할 수 있다. DB 멱등키에서
        # 진 요청이 기존 메시지를 반환했다면, 그 요청이 쓴 여분 파일을 지운다.
        if sent.attachment is None or sent.attachment.file_id != file_id:
            report_pdf_storage.delete(file_id)
        return sent
    except trainer_service.IdempotencyConflict as exc:
        if file_id:
            report_pdf_storage.delete(file_id)
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except report_pdf_storage.PdfStorageError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    except Exception:
        # DB/notification 저장이 완료되지 않았다면 고립 파일을 남기지 않는다.
        if file_id:
            db.rollback()
            persisted = db.scalar(
                select(ChatMessage.id).where(ChatMessage.attachment_file_id == file_id)
            )
            if persisted is None:
                report_pdf_storage.delete(file_id)
        raise


@router.post(
    "/trainer/clients/{member_id}/chat/image",
    response_model=ChatMessageOut,
    status_code=201,
)
async def trainer_send_chat_image(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    image: UploadFile = File(...),
    message: str = Form("", max_length=2000),
    client_request_id: str | None = Form(None, min_length=1, max_length=64),
) -> ChatMessageOut:
    """담당 고객에게 사진을 보낸다. (#921)

    자세 사진·시범 이미지는 코칭에서 가장 자주 오가는 형식인데, 지금까지 채팅에
    붙일 수 있는 것은 주간 리포트 PDF 하나뿐이었다.

    형식은 **바이트를 보고 판정한다.** 확장자와 `Content-Type` 은 보내는 쪽이
    자유롭게 적을 수 있어, 그 말을 믿으면 `image/png` 라고 적힌 아무 파일이나
    저장된다.
    """
    link = _require_client(db, trainer.id, member_id)
    if not link.active:
        raise HTTPException(status_code=404, detail="담당 고객을 찾을 수 없습니다.")
    text = message.strip()

    # 재시도는 기존 메시지를 바로 돌려줘 파일을 다시 쓰지 않는다(PDF 와 같은 규약).
    if client_request_id:
        existing = trainer_service.find_message_by_client_request(
            db, trainer.id, member_id, "trainer", client_request_id
        )
        if existing is not None:
            if existing.body != text or existing.attachment_type != "image":
                raise HTTPException(
                    status_code=409,
                    detail="같은 client_request_id에 다른 메시지를 보낼 수 없습니다.",
                )
            return trainer_service.chat_message_out(existing, "trainer")

    settings = get_settings()
    data = await image.read(settings.max_chat_image_bytes + 1)
    if len(data) > settings.max_chat_image_bytes:
        raise HTTPException(status_code=413, detail="이미지 용량이 너무 큽니다.")
    try:
        chat_image_storage.sniff(data)
    except chat_image_storage.UnsupportedImage as exc:
        raise HTTPException(status_code=415, detail=str(exc)) from exc

    display_name = re.sub(
        r"[\x00-\x1f]", "_", PurePath(image.filename or "photo").name
    ) or "photo"
    # DB 컬럼 길이를 넘는 사용자 filename이 메시지 저장을 깨지 않게 한다.
    if len(display_name) > 255:
        display_name = display_name[:255]

    file_id: str | None = None
    try:
        file_id, _, _ = chat_image_storage.save(data)
        sent = trainer_service.send_message(
            db,
            trainer.id,
            member_id,
            "trainer",
            text,
            notify=notification_service.TRAINER_MESSAGE,
            client_request_id=client_request_id,
            attachment_type="image",
            attachment_file_name=display_name,
            attachment_file_id=file_id,
            attachment_file_size=len(data),
        )
        # 동시 재시도 두 건이 모두 사전 조회를 통과할 수 있다. DB 멱등키에서
        # 진 요청이 기존 메시지를 반환했다면, 그 요청이 쓴 여분 파일을 지운다.
        if sent.attachment is None or sent.attachment.file_id != file_id:
            chat_image_storage.delete(file_id)
        return sent
    except trainer_service.IdempotencyConflict as exc:
        if file_id:
            chat_image_storage.delete(file_id)
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except chat_image_storage.ImageStorageError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    except Exception:
        # DB/notification 저장이 완료되지 않았다면 고립 파일을 남기지 않는다.
        if file_id:
            db.rollback()
            persisted = db.scalar(
                select(ChatMessage.id).where(
                    ChatMessage.attachment_file_id == file_id
                )
            )
            if persisted is None:
                chat_image_storage.delete(file_id)
        raise


# ---------------------------------------------------------------------------
# 프로그램 템플릿 — 어느 회원에게든 끼워 넣는 블록. (#920)
#
# 초안(`/trainer/programs`)과 답하는 질문이 다르다. 초안은 "이 회원에게 짜 둔
# 프로그램", 템플릿은 "내가 반복해 쓰는 구성"이다. 저장된 것이 없는 트레이너에게는
# 서버가 읽기 전용 시작 구성을 돌려준다 — 빈 화면으로 시작하면 이 기능이 무엇인지
# 알 수 없다. 시작 구성은 고치는 순간 그 트레이너의 첫 템플릿으로 새로 저장된다.
# ---------------------------------------------------------------------------


@router.get(
    "/trainer/program-templates", response_model=list[TrainerProgramTemplateOut]
)
def trainer_program_templates(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[TrainerProgramTemplateOut]:
    """내 템플릿(최근 수정 먼저). 하나도 없으면 시작 구성."""
    return trainer_program_template_service.list_templates(db, trainer.id)


@router.post(
    "/trainer/program-templates",
    response_model=TrainerProgramTemplateOut,
    status_code=201,
)
def create_trainer_program_template(
    payload: TrainerProgramTemplateCreate,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerProgramTemplateOut:
    try:
        return trainer_program_template_service.create_template(
            db,
            trainer.id,
            name=payload.name,
            goal=payload.goal,
            exercises=payload.exercises,
        )
    except trainer_program_template_service.TemplateLimitReached as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.put(
    "/trainer/program-templates/{template_id}",
    response_model=TrainerProgramTemplateOut,
)
def update_trainer_program_template(
    template_id: str,
    payload: TrainerProgramTemplateUpdate,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerProgramTemplateOut:
    try:
        return trainer_program_template_service.update_template(
            db, trainer.id, template_id, payload.model_dump(exclude_unset=True)
        )
    except trainer_program_template_service.TemplateNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.delete("/trainer/program-templates/{template_id}", status_code=200)
def delete_trainer_program_template(
    template_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    try:
        trainer_program_template_service.delete_template(
            db, trainer.id, template_id
        )
    except trainer_program_template_service.TemplateNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"status": "deleted"}


# ---------------------------------------------------------------------------
# 담당 요청 — 관계가 성립하는 **반대 방향**. (#919)
#
# 지금까지 담당이 생기는 경로는 회원이 상담을 요청하고 트레이너가 수락하는 하나
# 뿐이라, 센터에서 먼저 등록·결제를 마친 회원을 트레이너가 콘솔에서 잡을 수
# 없었다. 여기서 트레이너가 보내는 것은 **요청**이고, 담당 링크를 만드는 것은
# 회원의 수락(`POST /me/coach/invites/{id}/accept`)뿐이다 — 담당은 상대의
# 식단·건강 기록을 여는 권한이라 한쪽이 일방적으로 만들 수 없어야 한다.
# ---------------------------------------------------------------------------


@router.post(
    "/trainer/pairing-code/preview",
    response_model=PairedMemberOut,
    dependencies=[Depends(rate_limit("pairing-redeem"))],
)
def trainer_preview_pairing_code(
    payload: PairingCodeRedeem,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> PairedMemberOut:
    """코드가 가리키는 회원을 **연결하지 않고** 보여 준다. (#1634)

    여섯 자리를 잘못 누르면 남의 식단·건강 기록이 열린다. 되돌릴 수 없는
    사고라, 연결 전에 이름·성별·나이·목표를 눈으로 확인시킨다.

    코드를 태우지 않는다 — 확인하고 그만두는 것이 정상 흐름이고, 그때마다
    회원이 코드를 다시 띄워야 할 이유가 없다. 연결(`POST /trainer/pairing-code`)
    이 쓰는 순간에만 사라진다.

    소비와 같은 rate limit 버킷을 쓴다. 확인도 코드를 맞혀 보는 시도다.
    """
    try:
        return trainer_client_invite_service.preview_pairing_code(
            db, trainer.id, payload.code
        )
    except member_pairing_service.CodeNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_client_invite_service.MemberNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_client_invite_service.MemberAlreadyCoached as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post(
    "/trainer/pairing-code",
    response_model=PairedMemberOut,
    dependencies=[Depends(rate_limit("pairing-redeem"))],
)
def trainer_redeem_pairing_code(
    payload: PairingCodeRedeem,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> PairedMemberOut:
    """회원이 띄운 6자리 동기화 코드로 담당 관계를 **바로** 만든다. (#1634)

    담당 요청과 달리 회원의 수락을 기다리지 않는다. 코드를 발급해 불러 준 것이
    회원 본인이고 그 화면이 공유 범위를 말한다 — 이미 받은 동의를 한 번 더
    받을 이유가 없다.

    **코드가 맞는지만 확인하는 조회는 두지 않는다.** 소비하지 않는 확인이
    있으면 100만 조합을 훑을 수 있다. 이 호출 한 번이 확인이자 소비이고, 그
    위에 rate limit 이 얹힌다.

    코드가 틀렸는지·만료됐는지·이미 쓰였는지는 구분해 알려 주지 않는다(404).
    갈라 주면 어떤 코드가 존재하기는 했는지를 알려 주는 셈이다.
    """
    try:
        return trainer_client_invite_service.redeem_pairing_code(
            db, trainer.id, payload.code
        )
    except member_pairing_service.CodeNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_client_invite_service.MemberNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_client_invite_service.MemberAlreadyCoached as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except member_pairing_service.PairingError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.get("/trainer/client-invites", response_model=list[TrainerClientInviteOut])
def trainer_client_invites(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    status: str = Query("pending", pattern="^(pending|all)$"),
) -> list[TrainerClientInviteOut]:
    """내가 보낸 담당 요청."""
    return trainer_client_invite_service.list_sent(db, trainer.id, status=status)


@router.post(
    "/trainer/client-invites",
    response_model=TrainerClientInviteOut,
    status_code=201,
)
def create_trainer_client_invite(
    payload: TrainerClientInviteCreate,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerClientInviteOut:
    """담당 요청을 보낸다. 명단에는 아직 아무것도 생기지 않는다."""
    try:
        return trainer_client_invite_service.invite(
            db, trainer.id, payload.member_id, payload.message
        )
    except trainer_client_invite_service.MemberNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_client_invite_service.NotAMember as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except (
        trainer_client_invite_service.MemberAlreadyCoached,
        trainer_client_invite_service.DuplicatePendingInvite,
    ) as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.delete("/trainer/client-invites/{invite_id}", status_code=200)
def cancel_trainer_client_invite(
    invite_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """보낸 요청을 거둬들인다."""
    try:
        trainer_client_invite_service.cancel(db, trainer.id, invite_id)
    except trainer_client_invite_service.InviteNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_client_invite_service.InviteAlreadyDecided as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"status": "cancelled"}


# ---------------------------------------------------------------------------
# 상담 인박스 — 회원↔트레이너 관계가 성립하는 지점. (#467)
#
# 회원이 보낸 상담 요청(POST /consultations)은 지금까지 pending 으로 저장된 뒤
# 아무도 볼 수 없었다. 승인이 곧 담당 링크(trainer_clients) 생성이고, 그 링크 위에서
# 고객 목록·루틴·리포트·채팅이 동작한다.
# ---------------------------------------------------------------------------


@router.get("/trainer/consultations", response_model=list[TrainerConsultationOut])
def trainer_consultations(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    status: Annotated[ConsultationStatusFilter, Query()] = "pending",
    limit: int = Query(
        DEFAULT_PAGE, ge=1, le=MAX_PAGE, description="한 번에 가져올 요청 수"
    ),
    before: str | None = Query(
        None, description="ISO datetime 커서(다음 쪽) — 받은 마지막 요청의 created_at"
    ),
    before_id: str | None = Query(
        None, description="복합 커서 tie-break — 받은 마지막 요청의 id"
    ),
) -> list[TrainerConsultationOut]:
    """나를 지정한 상담 요청 한 쪽. 기본은 미처리만, 최신 50건. (#980)

    미처리 배지(`/trainer/consultations/pending-count`)는 이 쪽 나눔과 무관하게
    전체를 센다 — 배지가 첫 쪽 안에서만 세어지면 인박스가 길어질수록 조용히 줄어든다.
    """
    return consultation_service.list_for_trainer(
        db,
        trainer.id,
        status,
        limit=limit,
        before=parse_before(before),
        before_id=before_id,
    )


@router.get("/trainer/consultations/pending-count", response_model=dict[str, int])
def trainer_consultations_pending_count(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict[str, int]:
    """인박스 배지용 미처리 건수."""
    return {"count": consultation_service.pending_count_for_trainer(db, trainer.id)}


@router.post(
    "/trainer/consultations/{consultation_id}/accept",
    response_model=ConsultationAcceptOut,
)
def trainer_accept_consultation(
    consultation_id: str,
    payload: ConsultationAccept,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ConsultationAcceptOut:
    """상담을 승인하고 회원을 담당 고객으로 편입한다."""
    try:
        return consultation_service.accept(
            db,
            trainer.id,
            consultation_id,
            note=payload.note,
            schedule_date=payload.date,
            schedule_time=payload.time,
            schedule_type=payload.type,
            duration_minutes=payload.duration_minutes,
        )
    except consultation_service.ConsultationNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except (
        consultation_service.ConsultationAlreadyDecided,
        consultation_service.MemberAlreadyCoached,
    ) as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except consultation_service.ConsultationScheduleConflict as exc:
        raise HTTPException(
            status_code=409,
            detail={
                "message": str(exc),
                "conflicts": [
                    conflict.model_dump(mode="json") for conflict in exc.conflicts
                ],
            },
        ) from exc


@router.post(
    "/trainer/consultations/{consultation_id}/reject",
    response_model=TrainerConsultationOut,
)
def trainer_reject_consultation(
    consultation_id: str,
    payload: ConsultationDecision,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerConsultationOut:
    """상담을 거절한다. 사유는 회원 알림 본문에 그대로 실린다."""
    return _decide(consultation_service.reject, db, trainer.id, consultation_id, payload)


# ---- 알림함 (#503) ----
#
# 회원용 `/notifications` 를 재사용할 수 없다 — `get_current_user` 가 트레이너
# 계정을 403 으로 막는 **회원 전용** 경로다(역할 분리). 저장되는 행은 같은
# `notifications` 테이블이고 `user_id` 가 일반 사용자 FK라 스키마 변경은 없다.

def _notification_out(row: Notification) -> TrainerNotificationOut:
    return TrainerNotificationOut(
        id=row.id,
        title=row.title,
        body=row.body,
        category=row.category,
        read=row.read,
        created_at=row.created_at,
        time_ago=notification_service.time_ago(row.created_at),
    )


@router.get("/trainer/notifications", response_model=list[TrainerNotificationOut])
def trainer_notifications(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[TrainerNotificationOut]:
    """트레이너가 받은 알림(최신순)."""
    rows = db.scalars(
        select(Notification)
        .where(Notification.user_id == trainer.id)
        .order_by(Notification.created_at.desc())
        .limit(_NOTIFICATION_LIMIT)
    ).all()
    return [_notification_out(row) for row in rows]


@router.get("/trainer/notifications/unread-count", response_model=dict)
def trainer_unread_notifications(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """사이드바 배지가 읽는 값."""
    count = db.scalar(
        select(func.count())
        .select_from(Notification)
        .where(Notification.user_id == trainer.id, Notification.read.is_(False))
    )
    return {"unread": int(count or 0)}


@router.post("/trainer/notifications/read-all")
def trainer_read_all_notifications(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    marked = db.execute(
        update(Notification)
        .where(Notification.user_id == trainer.id, Notification.read.is_(False))
        .values(read=True)
    ).rowcount
    db.commit()
    return {"marked_read": int(marked or 0)}


@router.post("/trainer/notifications/{notification_id}/read")
def trainer_read_notification(
    notification_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    row = db.scalar(
        select(Notification).where(
            Notification.id == notification_id,
            # 남의 알림은 존재조차 드러내지 않는다.
            Notification.user_id == trainer.id,
        )
    )
    if row is None:
        raise HTTPException(status_code=404, detail="알림을 찾을 수 없습니다.")
    row.read = True
    db.commit()
    return {"id": row.id, "read": True}
