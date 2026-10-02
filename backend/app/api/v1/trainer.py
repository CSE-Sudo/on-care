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
import uuid
from datetime import date as _date
from datetime import datetime, timezone
from pathlib import PurePath
from typing import Annotated, Literal

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    Query,
    Request,
    Response,
    UploadFile,
)
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.api.deps import RequireApprovedTrainer, RequireTrainer
from app.api.v1 import chat_attachments
from app.core import clock
from app.core.config import get_settings
from app.core.locale import Locale, RequestLocale
from app.core.pagination import DEFAULT_PAGE, MAX_PAGE, parse_before
from app.core.rate_limit import limiter, rate_limit
from app.core.security import hash_password, verify_password
from app.db.session import get_db
from app.models.models import (
    AccountDeletionReason,
    ChatMessage,
    ExerciseSession,
    HealthProfile,
    Notification,
    TrainerClient,
    TrainerProfile,
    User,
)
from app.schemas.text_limits import TEXT_LONG_MAX
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
from app.schemas.consultation_api import (
    ConsultationAccept,
    ConsultationAcceptOut,
    ConsultationDecision,
    ConsultationStatusFilter,
    TrainerConsultationOut,
)
from app.schemas.user import AccountDeleteRequest, PasswordChanged
from app.schemas.trainer_api import (
    ChatMessageOut, ChatSendRequest, ClientCoachMessageOut, ClientCoachOut,
    ClientCoachRequest, ClientDietEntryOut, ClientFeedbackOut, DeliveryOut,
    MemberHealthProfileOut, MemberHealthProfileUpdate,
    MemberWeeklyFeedbackOut,
    ReportGoalsOut,
    ReportGoalsSaveRequest,
    ReportFeedbackOut,
    ReportFeedbackSaveRequest,
    MemberReportSendsOut,
    ReportSendRequest, ReportSendsOut, ReportSummaryOut,
    RoutineAssignRequest, RoutineOut, RoutineHistoryOut,
    RoutineSuggestionApproveRequest, RoutineSuggestionCreateRequest,
    ProgramAssignRequest, ProgramScheduleOut, ProgramScheduleRequest,
    RoutineOptionsOut, RoutineOptionsRequest, RoutineUpdateRequest,
    ScheduleCancelRequest, ScheduleCompleteRequest,
    ScheduleRoutineSendRequest,
    ScheduleRoutineUpdateRequest,
    ScheduleProgramSendRequest, ScheduleCreateRequest,
    ScheduleRecurringPreviewOut, ScheduleRecurringRequest, ScheduleReopenRequest,
    ScheduleSessionOut, ScheduleUpdateRequest,
    PairedMemberOut,
    PairingCodeRedeem,
    TrainerClientInviteCreate, TrainerClientInviteOut,
    TrainerClientOut, TrainerClientStatusOut, TrainerClientStatusUpdate,
    FollowUpScope,
    TrainerFollowUpTaskCreateRequest, TrainerFollowUpTaskOut,
    TrainerFollowUpTaskUpdateRequest,
    TrainerGymAffiliation, TrainerGymCandidate, TrainerKakaoGymSelect,
    TrainerMe, TrainerMeUpdate,
    TrainerMemoCreateRequest, TrainerMemoOut, TrainerMemoUpdateRequest,
    TrainerProgramDraftCreate, TrainerProgramDraftOut,
    TrainerProgramDraftSummary, TrainerProgramDraftUpdate,
    TrainerProgramTemplateCreate, TrainerProgramTemplateOut,
    TrainerProgramTemplateUpdate,
    TrainerNotificationOut, TrainerNotificationSettings, TrainerNotificationSettingsUpdate,
    TrainerPasswordChange, WeeklyReportOut,
    TrainerTaskKeyChange,
    TrainerTaskProgressDayOut, TrainerTaskProgressOut, TrainerTaskProgressSave,
)
from app.services import (
    audit,
    auth_tokens,
    client_feedback_service,
    diet_service,
    diet_trainer_analysis,
    diet_trainer_pick,
    emote_service,
    exercise_service,
    consultation_service,
    data_consent_service,
    health_goal_change,
    member_pairing_service,
    trainer_client_invite_service,
    trainer_program_template_service,
    diet_photo_service,
    notification_service,
    notification_templates,
    trainer_report_summary_service,
    report_pdf_storage,
    attachment_cleanup,
    trainer_routine_options_service,
    trainer_gym_search,
    trainer_service,
    trainer_task_progress_service,
)
from app.services.coach import conversation
from app.services.exercise_service import (
    build_current_week, monday_of_str, monday_of_this_week_str,
    pt_session_times, weekly_goals,
)
from app.services.coach.chat import answer as coach_answer

router = APIRouter(tags=["trainer"])

#: 트레이너 알림함 다음 쪽 커서를 싣는 응답 헤더(#2293). 본문은 전과 같은 배열로
#: 두어 기존 클라이언트가 그대로 읽고, 다음 쪽이 있을 때만 두 헤더가 붙는다.
#: 값은 쿼리 `before`·`before_id` 에 그대로 되돌려 준다. 브라우저(트레이너 웹)가
#: 읽을 수 있게 CORS `expose_headers` 에도 올린다(`app/main.py`).
NEXT_BEFORE_HEADER = "X-Next-Before"
NEXT_BEFORE_ID_HEADER = "X-Next-Before-Id"

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
    """(trainer, member) **살아 있는** 담당 링크를 확인한다. 없으면 404(소유권 경계).

    담당 해제는 행을 지우지 않고 `active=False` 로 내린다(`remove_client`). 행이
    있는지만 보면 해제된 회원의 식단·사진·채팅·루틴·메모·리포트·일정을 해제 뒤에도
    읽고 쓸 수 있으므로 `active` 까지 본다. (#2281)

    해제된 회원도 남의 회원·없는 회원과 **같은 404·같은 문구**다 — 다른 답을 주면
    "예전에 담당했던 회원" 이라는 사실이 응답만으로 드러난다. 해제된 링크를
    다뤄야 하는 곳(담당 해제 자체·재등록·활성/휴면 전환)은 이 함수를 쓰지 않고
    링크를 직접 읽는다.

    데이터 공유 동의가 철회된 뒤 새 동의 없이 살아 있는 링크도 같은 404 다
    (#1631). 담당 해제가 곧 동의 철회이고, 링크를 되살려도 회원의 새 동의가
    없으면 기록은 열리지 않는다.
    """
    link = db.scalar(
        select(TrainerClient).where(
            TrainerClient.trainer_id == trainer_id,
            TrainerClient.member_id == member_id,
        )
    )
    if (
        link is None
        or not link.active
        or data_consent_service.blocks_access(link)
    ):
        raise HTTPException(status_code=404, detail="담당 고객을 찾을 수 없습니다.")
    return link


#: 열람 감사 대상 기록 종류(#2830). 트레이너가 만든 루틴·메모·채팅처럼 두 사람이
#: 함께 쓰는 기록은 넣지 않는다 — 회원이 남긴 건강정보를 읽는 경로만이다.
CLIENT_READ_RESOURCES = frozenset({"diet", "exercise", "body", "report"})


def _audit_client_read(resource: str):
    """회원 기록 조회 라우트에 붙이는 열람 감사 의존성(#2830).

    `dependencies=[_audit_client_read("diet")]` 처럼 붙인다. 라우트 본문이 쓰는
    [_require_client] 와 같은 기준(활성 링크·동의 유효)을 통과할 때만 남긴다 —
    남의 회원·해제된 회원 요청은 본문이 어차피 404 로 끝내므로 열람이 아니다.
    같은 (트레이너, 회원, 자원)은 설정한 시간 안에 한 번만 남기고(묶음 규칙),
    기록 실패는 조회를 막지 않는다. 기록 내용은 누가·누구의·무엇을·언제뿐이다.
    """
    if resource not in CLIENT_READ_RESOURCES:  # pragma: no cover - 개발 실수 방지
        raise ValueError(f"알 수 없는 열람 자원: {resource}")

    def dependency(
        member_id: str,
        request: Request,
        trainer: RequireTrainer,
        db: Annotated[Session, Depends(get_db)],
    ) -> None:
        link = db.scalar(
            select(TrainerClient).where(
                TrainerClient.trainer_id == trainer.id,
                TrainerClient.member_id == member_id,
            )
        )
        if (
            link is None
            or not link.active
            or data_consent_service.blocks_access(link)
        ):
            return
        audit.record_client_read(
            db,
            trainer_id=trainer.id,
            member_id=member_id,
            resource=resource,
            ip=audit.client_ip(request),
        )

    return Depends(dependency)


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
    except trainer_service.GymTextNotEditable as e:
        # 값이 틀린 게 아니라 헬스장 정보가 소속에서만 파생되는 것과 충돌하는 것이라
        # 422 가 아니라 409.
        raise HTTPException(
            status_code=409,
            detail="헬스장 정보는 직접 수정할 수 없습니다. "
                   "헬스장을 검색해 소속을 설정하세요.",
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


@router.get("/trainer/gyms/search", response_model=list[TrainerGymCandidate])
async def trainer_search_gyms(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    query: str = Query(min_length=1, max_length=100, description="헬스장 이름·주소"),
    lat: float | None = Query(None, ge=-90, le=90, description="거리순 정렬용 위도"),
    lng: float | None = Query(None, ge=-180, le=180),
) -> list[TrainerGymCandidate]:
    """소속으로 고를 헬스장 검색. (#2543)

    등록된 헬스장을 먼저, 카카오에서 찾은 헬스장을 뒤에 싣는다. 카카오 키가 없거나
    호출이 실패하면 등록된 헬스장만 나온다.
    """
    if (lat is None) != (lng is None):
        raise HTTPException(status_code=422, detail="lat 과 lng 는 함께 보내야 합니다.")
    q = query.strip()
    if not q:
        raise HTTPException(status_code=422, detail="검색어를 입력하세요.")
    return await trainer_gym_search.search(db, q, lat, lng)


@router.put("/trainer/me/gym/kakao", response_model=TrainerMe)
async def trainer_set_kakao_gym(
    payload: TrainerKakaoGymSelect,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerMe:
    """카카오 검색 결과로 소속 설정. 처음 고른 헬스장은 이때 `places` 에 들어간다. (#2543)

    서버가 카카오를 다시 검색해 확인하므로, 헬스장이 아니거나 찾을 수 없으면 404,
    카카오를 쓸 수 없으면 503 이다.
    """
    profile = _require_profile(db, trainer.id)
    try:
        me = await trainer_gym_search.select_kakao_gym(
            db, trainer, profile, payload.kakao_place_id, payload.name.strip()
        )
    except trainer_gym_search.GymLookupUnavailable as e:
        raise HTTPException(
            status_code=503, detail="지금은 헬스장을 확인할 수 없습니다. 잠시 뒤 다시 시도하세요."
        ) from e
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


@router.post("/trainer/me/password", status_code=200, response_model=PasswordChanged)
def trainer_change_password(
    payload: TrainerPasswordChange,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    request: Request,
) -> PasswordChanged:
    """비밀번호 변경. 현재 비밀번호가 맞아야 하고, 같은 값으로는 바꿀 수 없다.

    바꾸면 계정의 토큰 세대가 올라가 **다른 기기에 이미 나간 접근·refresh 토큰이
    모두 무효**가 된다(#2766) — 비밀번호를 바꾸는 이유는 대개 누가 계정을 쓰고
    있을지 모른다는 의심이다. 요청한 기기는 응답에 담긴 새 토큰으로 이어 쓴다.
    """
    if not verify_password(payload.current_password, trainer.hashed_password):
        # 현재 비밀번호 불일치는 401 이 아니라 400 — 토큰은 유효하므로
        # 클라이언트가 로그아웃 처리로 오인하면 안 된다.
        raise HTTPException(status_code=400, detail="현재 비밀번호가 일치하지 않습니다.")
    if verify_password(payload.new_password, trainer.hashed_password):
        raise HTTPException(status_code=400, detail="현재와 다른 비밀번호를 입력해 주세요.")
    trainer.hashed_password = hash_password(payload.new_password)
    # 비밀번호와 세대는 한 트랜잭션으로 — 하나만 반영되면 옛 토큰이 살아남거나
    # 비밀번호는 그대로인데 모든 기기가 끊긴다.
    auth_tokens.bump_version(trainer)
    # 변경 사실만 남긴다(#2830) — 비밀번호와 같은 트랜잭션이라 둘 중 하나만 남지 않는다.
    audit.stage(
        db,
        event=audit.PASSWORD_CHANGE,
        user_id=trainer.id,
        ip=audit.client_ip(request),
    )
    db.commit()
    tokens = auth_tokens.issue_token_pair(trainer)
    return PasswordChanged(
        access_token=tokens.access_token, refresh_token=tokens.refresh_token
    )


#: 트레이너 탈퇴 화면이 보여 주는 사유(#2264). 회원 사유(`DELETION_REASONS`)와 같은
#: 표에 남기되 `trainer_` 를 붙여 섞이지 않게 한다 — 표에는 누가 썼는지 없으니
#: 코드만으로 회원·트레이너를 가를 수 있어야 한다. 모르는 값은 버린다.
TRAINER_DELETION_REASONS: frozenset[str] = frozenset(
    {
        "rarely_used",
        "hard_to_use",
        "missing_feature",
        "leaving_work",
        "found_alternative",
        "other",
    }
)


@router.delete("/trainer/me")
def trainer_delete_me(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    request: Request,
    payload: AccountDeleteRequest | None = None,
) -> dict:
    """트레이너 탈퇴. 담당 회원에게 알린 뒤 계정과 딸린 데이터를 지운다. (#505)

    회원 탈퇴(`DELETE /users/me`)와 대칭이다. 담당 회원이 남아 있어도 막지 않는다 —
    막으면 담당이 있는 트레이너는 계정을 영영 지울 수 없다.

    고른 사유가 있으면 회원 탈퇴와 같은 표에 계정과 잇지 않고 남긴다(#2264).
    사유는 없어도 된다 — 탈퇴를 막는 조건이 아니라 물어보는 자리다.
    """
    for reason in sorted(
        set(payload.reasons if payload else []) & TRAINER_DELETION_REASONS
    ):
        db.add(
            AccountDeletionReason(
                id=f"del-{uuid.uuid4().hex[:12]}",
                reason=f"trainer_{reason}",
            )
        )
    # 동의 종료·탈퇴를 감사 기록으로 남긴다 — 삭제와 같은 트랜잭션이다(#2830).
    data_consent_service.stage_account_withdrawal(
        db, trainer, ip=audit.client_ip(request)
    )
    # 채팅 첨부의 바이트는 DB 밖에 있어 CASCADE 가 닿지 않는다 — 행이 사라지기
    # 전에 목록을 잡아 두고, 탈퇴 커밋이 끝난 뒤에 지운다(#2817).
    attachments = attachment_cleanup.files_in_threads(db, trainer_id=trainer.id)
    trainer_service.delete_trainer_account(db, trainer)
    attachment_cleanup.purge(attachments)
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
    emote_id = payload.emote_id
    if emote_id is not None:
        # 트레이너는 이용권 없이 보낸다(#2020) — 이용권은 회원이 포인트를 쓰는
        # 자리이고, 트레이너에게는 포인트라는 것이 없다. 아는 id 인지만 본다.
        if not emote_service.is_known(emote_id):
            raise HTTPException(status_code=400, detail="없는 이모티콘이에요.")
        text = text or "(이모티콘)"
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
            emote_id=emote_id,
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

@router.get(
    "/trainer/clients/{member_id}/deliveries/latest",
    response_model=DeliveryOut | None,
)
def trainer_latest_delivery(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> DeliveryOut | None:
    """이 회원에게 가장 최근에 보낸 것 한 묶음. (#2225)

    전송 이력이 PT 프로그램과 개인운동을 따로 나열하면, PT 완료 때 함께 보낸
    개인운동이 어느 PT 와 짝인지 알 수 없다(#2224). 보낸 적이 없으면 `null`.
    """
    _require_client(db, trainer.id, member_id)
    return trainer_service.latest_delivery(db, trainer.id, member_id)


@router.get(
    "/trainer/clients/{member_id}/routines/unsent",
    response_model=list[RoutineOut],
)
def trainer_unsent_personal_routines(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[RoutineOut]:
    """PT 에 붙여만 두고 아직 보내지 않은 개인운동. (#2225)

    지금은 그 사실이 스케줄 탭의 그 일정을 열어야만 보인다. 각 줄의
    `schedule_id` 로 어느 PT 의 것인지 알 수 있고, 보내는 것은 그 일정의
    `POST /trainer/schedule/{id}/routines/send` 가 맡는다(#2224).
    """
    _require_client(db, trainer.id, member_id)
    return trainer_service.unsent_personal_routines(db, trainer.id, member_id)


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
        duration_seconds=payload.duration_seconds,
        type_=payload.type, reason=payload.reason, source=payload.source,
        client_request_id=payload.client_request_id,
        exercise_date=payload.exercise_date,
        intensity=payload.intensity,
        sets=payload.sets,
        reps=payload.reps,
        hold_seconds=payload.hold_seconds,
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
        duration_seconds=payload.duration_seconds,
        type_=payload.type,
        sets=payload.sets,
        reps=payload.reps,
        hold_seconds=payload.hold_seconds,
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
            duration_seconds=fields.get("duration_seconds"),
            type_=fields.get("type"),
            sets=fields.get("sets"),
            reps=fields.get("reps"),
            hold_seconds=fields.get("hold_seconds"),
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
        delivery_kind=payload.delivery_kind,
        trainer_message=payload.trainer_message.strip(),
        start_date=payload.start_date,
        active_days=payload.active_days,
        suggestion_ids=payload.suggestion_ids,
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
    """배정한 루틴 수정(부분). 이름·시간(분 또는 초)·종류·사유만 바뀐다. (#504, #2547)

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

    운동 기록 메모(`exercise_memo`, #2332)는 `ref_id`(이력 카드) 또는
    `ref_date`(회원 직접 기록 카드)로 기록을 가리킨다. 트레이너 화면에 보이지
    않는 기록이면 404 다.
    """
    _require_client(db, trainer.id, member_id)
    body = payload.body.strip()
    if not body:
        # 공백만 있는 메모를 성공으로 처리하면 목록에 빈 줄이 쌓인다.
        raise HTTPException(status_code=400, detail="메모 내용이 필요합니다.")
    try:
        return trainer_service.create_memo(
            db, trainer.id, member_id,
            body=body,
            source=payload.source,
            insight_id=payload.insight_id,
            insight_kind=payload.insight_kind,
            ref_id=payload.ref_id,
            ref_date=payload.ref_date,
            category=payload.category,
        )
    except trainer_service.RoutineNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


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
    """메모 수정(부분). 본문과, 직접 쓴 메모의 분류가 바뀐다(#2622)."""
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
    except trainer_service.MemoCategoryLocked as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get(
    "/trainer/clients/{member_id}/feedbacks",
    response_model=list[ClientFeedbackOut],
)
def trainer_client_feedbacks(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[ClientFeedbackOut]:
    """담당 회원과 주고받은 피드백 모아 보기(최신 먼저, 최근 90일). (#2615)

    완료 PT 세션 피드백·보낸 주간 리포트(트레이너 → 회원)와 회원 주간
    피드백(회원 → 트레이너)을 한 목록으로 준다. 읽기 전용이다 — 고치는 곳은
    원래 자리 하나뿐이다. 해제·비담당 회원은 다른 회원 경로와 같은 404 다.
    """
    link = _require_client(db, trainer.id, member_id)
    return client_feedback_service.build_client_feedbacks(db, trainer.id, link)


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


@router.get("/trainer/dashboard/task-progress", response_model=TrainerTaskProgressOut)
def trainer_task_progress(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerTaskProgressOut:
    """오늘 할 일 진행 상태 — 보관 기간 안의 날짜별 기록. (#1633)

    기기 로컬이 아니라 계정 단위다. 센터 PC 에서 체크한 항목이 태블릿에서도
    체크돼 있어야 한다.
    """
    return trainer_task_progress_service.build_progress(db, trainer.id)


@router.put(
    "/trainer/dashboard/task-progress/{day}",
    response_model=TrainerTaskProgressDayOut,
)
def trainer_save_task_progress(
    day: str,
    payload: TrainerTaskProgressSave,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerTaskProgressDayOut:
    """그날의 진행 상태를 통째로 저장한다. KST 오늘·어제만 받는다."""
    if not _is_ymd(day):
        raise HTTPException(status_code=422, detail="날짜는 YYYY-MM-DD 형식이어야 합니다.")
    if day not in trainer_task_progress_service.writable_dates():
        raise HTTPException(
            status_code=422, detail="오늘 또는 어제(KST)만 저장할 수 있습니다."
        )
    return trainer_task_progress_service.save_day(db, trainer.id, day, payload)



@router.post(
    "/trainer/dashboard/task-progress/{day}/keys",
    response_model=TrainerTaskProgressDayOut,
)
def trainer_change_task_key(
    day: str,
    payload: TrainerTaskKeyChange,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerTaskProgressDayOut:
    """할 일 키 하나를 체크·해제·삭제한다. KST 오늘·어제만 받는다. (#2886)

    그날 전체를 덮어쓰지 않아, 다른 탭·기기에서 체크한 할 일이 남는다. 응답은
    반영 뒤의 그날 상태라 앱이 다른 기기의 변경까지 받아 그린다.
    """
    if not _is_ymd(day):
        raise HTTPException(status_code=422, detail="날짜는 YYYY-MM-DD 형식이어야 합니다.")
    if day not in trainer_task_progress_service.writable_dates():
        raise HTTPException(
            status_code=422, detail="오늘 또는 어제(KST)만 저장할 수 있습니다."
        )
    return trainer_task_progress_service.apply_key(db, trainer.id, day, payload)

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
    except trainer_service.ScheduleOverlap as exc:
        # 겹친 세션을 함께 실어 화면이 어느 일정과 겹치는지 짚게 한다. (#2284)
        raise HTTPException(
            status_code=409, detail=trainer_service.overlap_detail(exc)
        ) from exc


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
        duration_minutes=payload.duration_minutes,
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
                # 단건 겹침과 같은 코드 — 화면이 한 가지 규칙으로 알아본다. (#2284)
                "code": trainer_service.SCHEDULE_OVERLAP_CODE,
                "message": str(exc),
                "conflicts": [
                    conflict.model_dump(mode="json") for conflict in exc.conflicts
                ],
            },
        ) from exc
    except trainer_service.ScheduleError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post(
    "/trainer/clients/{member_id}/program-schedule",
    response_model=ProgramScheduleOut,
    status_code=201,
)
def trainer_assign_program_with_schedule(
    member_id: str,
    payload: ProgramScheduleRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ProgramScheduleOut:
    """프로그램 탭 `일정 추가` — 배정과 PT 일정 등록을 한 트랜잭션으로. (#1580)

    둘 중 하나만 반영되는 경우가 없다. `client_request_id` 는 명령 전체에 대해
    멱등하다 — 응답을 잃고 같은 키로 다시 보내면 먼저 처리한 결과가 돌아온다.
    """
    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="프로그램 이름이 필요합니다.")
    if not any(session.exercises for session in payload.sessions):
        raise HTTPException(status_code=400, detail="운동이 하나 이상 필요합니다.")
    try:
        result = trainer_service.assign_program_with_schedule(
            db,
            trainer.id,
            member_id,
            name=name,
            sessions=payload.sessions,
            date=payload.date,
            time=payload.time,
            duration_minutes=payload.duration_minutes,
            client_name=payload.client_name,
            client_request_id=payload.client_request_id,
            session_id=payload.session_id,
            personal_routines=payload.personal_routines,
            suggestion_ids=payload.suggestion_ids,
        )
    except trainer_service.IdempotencyConflict as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except trainer_service.ScheduleOverlap as exc:
        raise HTTPException(
            status_code=409, detail=trainer_service.overlap_detail(exc)
        ) from exc
    except trainer_service.AttachTargetConflict as exc:
        # 겹치는 후보를 함께 실어 화면이 어느 회차를 고를지 다시 물을 수 있게 한다.
        raise HTTPException(
            status_code=409,
            detail={
                "code": exc.code,
                "message": str(exc),
                "candidates": [
                    candidate.model_dump(mode="json") for candidate in exc.candidates
                ],
            },
        ) from exc
    if result is None:
        raise HTTPException(status_code=404, detail="담당 고객을 찾을 수 없습니다.")
    return result


@router.get(
    "/trainer/schedule/{session_id}/routines", response_model=list[RoutineOut]
)
def trainer_schedule_routines(
    session_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[RoutineOut]:
    """그 PT 일정에 붙어 있는(아직 회원에게 가지 않은) 개인운동. (#2223)

    일정 상세가 "이 PT 와 함께 갈 개인운동"을 보여 주는 데 쓴다(#2224). 보낸
    뒤에는 배정 목록(`GET .../routines`)으로 옮겨 가므로 여기서는 빠진다. 남의
    일정은 조건에서 걸러져 빈 목록이 된다 — 없는 일정과 같은 답이라 어느 id 가
    실재하는지 알려 주지 않는다.
    """
    return trainer_service.list_scheduled_routines(db, trainer.id, session_id)


@router.put(
    "/trainer/schedule/{session_id}/routines", response_model=list[RoutineOut]
)
def trainer_update_schedule_routines(
    session_id: str,
    payload: ScheduleRoutineUpdateRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[RoutineOut]:
    """그 PT 에 붙은 개인운동을 고친다 — 보내지는 않는다. (#2224)

    일정 상세에서 바로 고친다. 이미 보낸 것은 손댈 수 없다. 붙은 것이 없으면
    처음 붙인다(#2280) — 개인운동 단계를 지나지 않은 PT 를 구제하는 자리다.
    """
    try:
        rows = trainer_service.update_scheduled_routines(
            db,
            trainer.id,
            session_id,
            payload.personal_routines,
            suggestion_ids=payload.suggestion_ids,
        )
    except trainer_service.ClientLinkDetached as exc:
        # 해제·동의 철회된 회원의 일정 — 남의 회원과 같은 404. (#2281, #1631)
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_service.ScheduleError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if rows is None:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없습니다.")
    return rows


@router.post(
    "/trainer/schedule/{session_id}/routines/send",
    response_model=list[RoutineOut],
)
def trainer_send_schedule_routines(
    session_id: str,
    payload: ScheduleRoutineSendRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[RoutineOut]:
    """마무리된 PT 에 남은 개인운동을 회원에게 보낸다. (#2224)

    취소·노쇼로 끝난 PT 의 개인운동은 자동으로 가지 않는다 — 아파서 쉬는
    회원에게 운동이 저절로 가면 안 된다. 트레이너가 누를 때만 온다.
    `personal_routines` 를 주면 그 내용으로 고쳐서 보낸다.
    """
    try:
        sent = trainer_service.send_scheduled_routines(
            db, trainer.id, session_id, items=payload.personal_routines
        )
    except trainer_service.ClientLinkDetached as exc:
        # 해제·동의 철회된 회원의 일정 — 남의 회원과 같은 404. (#2281, #1631)
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_service.ScheduleError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if sent is None:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없습니다.")
    return sent


@router.post("/trainer/schedule/{session_id}/routines/dismiss")
def trainer_dismiss_schedule_routines(
    session_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict[str, bool]:
    """마무리된 PT 의 개인운동을 보내지 않기로 정리한다. (#2224)

    `개인운동 미전송` 표시를 걷어낸다. 무엇을 짰다가 안 보냈는지는 남는다.
    """
    try:
        done = trainer_service.dismiss_scheduled_routines(
            db, trainer.id, session_id
        )
    except trainer_service.ScheduleError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if done is None:
        raise HTTPException(status_code=404, detail="일정을 찾을 수 없습니다.")
    return {"dismissed": done}


@router.put("/trainer/schedule/{session_id}", response_model=ScheduleSessionOut)
def trainer_update_session(
    session_id: str,
    payload: ScheduleUpdateRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ScheduleSessionOut:
    """예약 수정(제공된 필드만). member_id 변경 시 담당 고객이어야 한다.
    완료·취소·노쇼 세션은 기록과의 정합성을 위해 메모·아직 보내지 않은
    프로그램만 수정할 수 있다(그 밖은 409, #2754)."""
    fields = payload.model_dump(exclude_unset=True)
    if fields.get("member_id"):
        _require_client(db, trainer.id, fields["member_id"])
    try:
        out = trainer_service.update_session(db, trainer.id, session_id, fields)
    except trainer_service.ClientLinkDetached as e:
        # 해제·동의 철회된 회원의 일정 — 남의 회원과 같은 404. (#2281, #1631)
        raise HTTPException(status_code=404, detail=str(e)) from e
    except trainer_service.ScheduleOverlap as e:
        raise HTTPException(
            status_code=409, detail=trainer_service.overlap_detail(e)
        ) from e
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
    except trainer_service.ClientLinkDetached as e:
        # 해제·동의 철회된 회원의 일정 — 남의 회원과 같은 404. (#2281, #1631)
        raise HTTPException(status_code=404, detail=str(e)) from e
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
            db,
            trainer.id,
            session_id,
            new_date=payload.date,
            time=payload.time,
            duration_minutes=payload.duration_minutes,
        )
    except trainer_service.ClientLinkDetached as e:
        # 해제·동의 철회된 회원의 일정 — 남의 회원과 같은 404. (#2281, #1631)
        raise HTTPException(status_code=404, detail=str(e)) from e
    except trainer_service.ScheduleOverlap as e:
        # 겹치면 아무것도 바꾸지 않는다 — 완료·날짜·파생 기록이 그대로다. (#2757)
        raise HTTPException(
            status_code=409, detail=trainer_service.overlap_detail(e)
        ) from e
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
    except trainer_service.ClientLinkDetached as e:
        raise HTTPException(status_code=404, detail=str(e)) from e
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

    **분당 한도(#1548)** — 회원 AI 코치와 같은 `coach_chat_per_minute` 를 트레이너
    단위 버킷으로 센다. 넘기면 429 와 `Retry-After` 다. 같은 헬스장(같은 IP)의 다른
    트레이너가 한도를 대신 소진하지 않게 IP 가 아니라 트레이너 id 로 나눈다.
    """
    _require_client(db, trainer.id, member_id)
    settings = get_settings()
    if settings.rate_limit_enabled:
        limiter.check(
            f"trainer-coach-chat:trainer:{trainer.id}",
            settings.coach_chat_per_minute,
            60.0,
        )
    message = payload.message.strip()
    if not message:
        raise HTTPException(status_code=400, detail="메시지가 비어 있습니다.")

    # 이 트레이너 전용 스레드다(#588). 검색 스코프는 회원이지만 문답의 주인은
    # 트레이너라, 회원 대화(trainer_id IS NULL)와 섞이면 회원이 앱을 열었을 때
    # 자기가 하지 않은 대화를 보게 된다.
    history = conversation.load_messages(db, member_id, trainer_id=trainer.id)
    reply, sources, _ = coach_answer(db, member_id, message, history)
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


@router.get(
    "/trainer/clients/{member_id}/report",
    response_model=WeeklyReportOut,
    dependencies=[_audit_client_read("report")],
)
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
    dependencies=[_audit_client_read("report")],
)
def trainer_client_report_summary(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    locale: RequestLocale,
    week_start: str | None = Query(None, description="YYYY-MM-DD (기본: 이번 주)"),
) -> ReportSummaryOut:
    """그 주의 리포트 요약.

    리포트 본문과 **따로** 부른다. 생성에 몇 초가 걸리는데 한 응답에 묶으면
    고객을 고를 때마다 화면 전체가 그만큼 멈춘다.

    문장은 `Accept-Language` 언어로 만든다(#2298). 헤더가 없으면 한국어다.
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
        db,
        trainer.id,
        member_id,
        _report_week(week_start or trainer_service.today_iso()),
        locale,
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


@router.get(
    "/trainer/clients/{member_id}/report/member-feedback",
    response_model=MemberWeeklyFeedbackOut,
    dependencies=[_audit_client_read("report")],
)
def trainer_client_member_weekly_feedback(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    week_start: str | None = Query(None, description="YYYY-MM-DD (기본: 이번 주)"),
) -> MemberWeeklyFeedbackOut:
    """회원이 그 주에 스스로 남긴 세 문항. (#2232)

    리포트의 `회원 주간 피드백` 칸이 읽는다. 수치만 보면 같은 한 주가 `게으름`
    으로도 `과부하·일정 문제` 로도 읽히는데, 이 한 줄이 그 판단을 바꾼다.

    아직 답하지 않았으면 `submitted=false` 로 답한다 — 오류가 아니다.
    """
    _require_client(db, trainer.id, member_id)
    return trainer_service.get_member_weekly_feedback(
        db, member_id, _report_week(week_start or trainer_service.today_iso())
    )


@router.get(
    "/trainer/clients/{member_id}/report/goals",
    response_model=ReportGoalsOut,
    dependencies=[_audit_client_read("report")],
)
def trainer_client_report_goals(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    week_start: str | None = Query(None, description="YYYY-MM-DD (기본: 이번 주)"),
) -> ReportGoalsOut:
    """그 주에 **적용돼 있는** 목표 — 지난 주에 ② 에서 고른 것이다. (#2232)

    리포트의 `지난 주 목표 달성` 칸이 이걸 회수한다. 목표는 다음 주에 확인될
    때 비로소 목표이고, 확인되지 않는 목표를 매주 새로 고르는 화면은 트레이너
    에게 일만 늘린다.

    비어 있는 것은 오류가 아니다 — 지난 주에 아무것도 고르지 않았거나 이
    회원의 첫 주다.
    """
    _require_client(db, trainer.id, member_id)
    return trainer_service.get_report_goals(
        db, member_id, _report_week(week_start or trainer_service.today_iso())
    )


@router.put(
    "/trainer/clients/{member_id}/report/goals",
    response_model=ReportGoalsOut,
)
def trainer_save_report_goals(
    member_id: str,
    payload: ReportGoalsSaveRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> ReportGoalsOut:
    """② 에서 고른 목표를 **다음 주**에 적용한다. (#2232)

    `week_start` 는 지금 보고 있는 주이고, 적용되는 주는 서버가 한 주를 더해
    정한다 — 주 경계 계산이 앱과 서버 두 곳에 있으면 한쪽만 틀리는 날이 온다.
    응답의 `week_start` 는 **적용된 주**라, 앱이 저장 결과를 그대로 믿을 수 있다.

    PUT 인 까닭은 초안 저장과 같다: 화면이 들고 있는 목록 전체로 그 주의
    목표를 통째로 바꾸는 동작이라 여러 번 눌러도 결과가 같다.
    """
    _require_client(db, trainer.id, member_id)
    week = _report_week(payload.week_start or trainer_service.today_iso())
    return trainer_service.save_report_goals(
        db, trainer.id, member_id, week, payload.goals
    )


@router.get("/trainer/reports/sent", response_model=ReportSendsOut)
def trainer_report_sends(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    week_start: str | None = Query(None, description="YYYY-MM-DD (기본: 이번 주)"),
) -> ReportSendsOut:
    """그 주 리포트가 이미 나간 담당 회원들. (#2288)

    리포트 작업대가 `전송 완료` 열을 세우고, 이미 보낸 회원에게 다시 보내기
    전에 확인을 받는 근거다. 회원마다 따로 묻지 않고 한 번에 준다 — 작업대는
    로스터 전체를 한 화면에 세운다.
    """
    return trainer_service.list_report_sends(
        db, trainer.id, _report_week(week_start or trainer_service.today_iso())
    )


#: 회원별 지난 리포트 한 쪽의 기본 주 수. 석 달 남짓 — 한 화면에 세우는 선이다.
_REPORT_HISTORY_PAGE = 12


@router.get(
    "/trainer/clients/{member_id}/reports/sent",
    response_model=MemberReportSendsOut,
    dependencies=[_audit_client_read("report")],
)
def trainer_client_report_sends(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(
        _REPORT_HISTORY_PAGE, ge=1, le=MAX_PAGE, description="한 번에 가져올 주 수"
    ),
    before: str | None = Query(
        None, description="YYYY-MM-DD — 이 주보다 이전 주만(앞 쪽의 next_before)"
    ),
) -> MemberReportSendsOut:
    """담당 회원에게 그동안 보낸 리포트, 주별로 최신 주부터. (#2393)

    주 단위 조회(`/trainer/reports/sent`)는 한 주의 로스터 전체를 준다. 한
    회원의 지난 리포트를 보려면 주마다 따로 물어야 해 이 경로를 따로 둔다.
    해제·비담당 회원은 다른 회원 경로와 같은 404 다(#2281).
    """
    _require_client(db, trainer.id, member_id)
    cursor: _date | None = None
    if before is not None:
        if not _is_ymd(before):
            raise HTTPException(
                status_code=422, detail="before 는 YYYY-MM-DD 형식이어야 합니다."
            )
        cursor = _date.fromisoformat(before)
    return trainer_service.list_member_report_sends(
        db, trainer.id, member_id, limit=limit, before=cursor
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
    message: str = Form(...),
    client_request_id: str | None = Form(None, min_length=1, max_length=64),
) -> ChatMessageOut:
    """현재 리포트에서 생성한 PDF만 담당 고객 채팅으로 전송한다.

    `message` 는 필수이고 공백뿐이면 422 다(#2771). 서버가 대신 채우던 한국어
    기본 문장은 트레이너·회원의 언어를 몰라, 영어로 쓰는 회원에게도 한국어가
    나갔다 — 회원이 받을 글은 앱이 그 언어로 만든다.
    """
    _require_client(db, trainer.id, member_id)
    week = _report_week(week_start)
    text = message.strip()
    if not text:
        raise HTTPException(status_code=422, detail="리포트와 함께 보낼 메시지를 입력해 주세요.")

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
    message: str = Form("", max_length=TEXT_LONG_MAX),
    client_request_id: str | None = Form(None, min_length=1, max_length=64),
) -> ChatMessageOut:
    """담당 고객에게 사진을 보낸다. (#921)

    자세 사진·시범 이미지는 코칭에서 가장 자주 오가는 형식인데, 지금까지 채팅에
    붙일 수 있는 것은 주간 리포트 PDF 하나뿐이었다.

    형식은 **바이트를 보고 판정한다.** 확장자와 `Content-Type` 은 보내는 쪽이
    자유롭게 적을 수 있어, 그 말을 믿으면 `image/png` 라고 적힌 아무 파일이나
    저장된다.
    """
    _require_client(db, trainer.id, member_id)
    # 받는 규약은 회원 발신(#1665)과 한곳에서 나눠 쓴다.
    return await chat_attachments.receive_chat_image(
        db,
        trainer_id=trainer.id,
        member_id=member_id,
        sender="trainer",
        image=image,
        message=message,
        client_request_id=client_request_id,
        notify=notification_service.TRAINER_MESSAGE,
    )


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
    trainer: RequireApprovedTrainer,  # 승인 전 403(#2825)
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
    trainer: RequireApprovedTrainer,  # 승인 전 403(#2825)
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
    trainer: RequireApprovedTrainer,  # 승인 전 403(#2825)
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
    """상담을 수락하고 회원이 고른 자리에 상담 일정을 잡는다.

    담당 연결(등록)은 만들지 않는다 — 등록은 상담 뒤 6자리 연결 코드로 한다(#2584).
    시각을 받지 않는다 — 회원이 신청할 때 고른 자리가 날짜·시각·길이를 이미 들고
    있다(#1873).
    """
    try:
        return consultation_service.accept(
            db, trainer.id, consultation_id, note=payload.note
        )
    except consultation_service.ConsultationNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_service.ScheduleOverlap as exc:
        # 회원이 고른 자리에 그 사이 트레이너가 다른 일정을 잡았다. (#2284)
        raise HTTPException(
            status_code=409, detail=trainer_service.overlap_detail(exc)
        ) from exc
    except (
        consultation_service.ConsultationAlreadyDecided,
        consultation_service.ConsultationSlotGone,
    ) as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


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

def _notification_out(row: Notification, locale: Locale) -> TrainerNotificationOut:
    """트레이너 알림 한 건. 제목·본문은 요청 언어로 조립한다(#2302).

    트레이너 웹은 `template`·`args` 로 ARB 문장을 직접 조립하고, 모르는 틀일 때만
    `title`·`body` 를 쓴다. 그 값도 요청 언어라, 새 틀을 아직 모르는 빌드도 알맞은
    언어로 보인다. 한국어이거나 틀이 없는 옛 알림은 저장된 문장 그대로다.
    """
    title, body = notification_templates.localize(
        title=row.title,
        body=row.body,
        template=row.template,
        template_args=row.template_args,
        locale=locale,
    )
    return TrainerNotificationOut(
        id=row.id,
        title=title,
        body=body,
        category=row.category,
        read=row.read,
        created_at=row.created_at,
        time_ago=notification_service.time_ago(row.created_at, locale),
        subject_id=row.subject_id,
        template=row.template,
        args=row.template_args,
        target_date=row.target_date,
    )


def _cursor_value(moment: datetime) -> str:
    """커서 헤더에 싣는 시각. `parse_before` 가 그대로 읽는 ISO 형식(UTC)이다."""
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(timezone.utc).isoformat()


@router.get("/trainer/notifications", response_model=list[TrainerNotificationOut])
def trainer_notifications(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    locale: RequestLocale,
    response: Response,
    limit: int = Query(
        notification_service.TRAINER_PAGE_DEFAULT,
        ge=1,
        le=notification_service.TRAINER_PAGE_MAX,
        description="한 번에 가져올 최신 알림 수",
    ),
    before: str | None = Query(
        None, description="ISO datetime 커서(다음 쪽) — 받은 마지막 알림의 created_at"
    ),
    before_id: str | None = Query(
        None, description="복합 커서 tie-break — 받은 마지막 알림의 id"
    ),
) -> list[TrainerNotificationOut]:
    """트레이너가 받은 알림 한 쪽(최신순). 다음 쪽은 커서로 이어 받는다. (#2293)

    파라미터 없이 부르면 전처럼 최신 100건이다. 다음 쪽이 있으면
    `X-Next-Before`·`X-Next-Before-Id` 헤더에 커서가 실리고, 없으면 두 헤더가
    없다 — 그게 마지막 쪽이라는 뜻이다.

    미읽음 배지(`/trainer/notifications/unread-count`)와 모두 읽음은 쪽 나눔과
    무관하게 이 트레이너의 알림 전체를 대상으로 한다.
    """
    cursor = parse_before(before)
    if before_id is not None and cursor is None:
        # tie-break 만 오면 어디서 자를지 알 수 없다. 조용히 첫 쪽을 주면
        # 클라이언트가 같은 알림을 다시 이어 붙인다.
        raise HTTPException(
            status_code=422, detail="before_id 는 before 와 함께 보내야 합니다."
        )
    rows, last = notification_service.list_for_trainer(
        db, trainer.id, limit=limit, before=cursor, before_id=before_id
    )
    if last is not None:
        response.headers[NEXT_BEFORE_HEADER] = _cursor_value(last.created_at)
        response.headers[NEXT_BEFORE_ID_HEADER] = last.id
    return [_notification_out(row, locale) for row in rows]


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
