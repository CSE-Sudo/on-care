"""트레이너 라우터 — 주간 리포트(트레이너 → 회원)."""
from __future__ import annotations

import re
from datetime import date as _date
from pathlib import PurePath
from typing import Annotated

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    Query,
    UploadFile,
)
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import RequireTrainer
from app.core.config import get_settings
from app.core.locale import RequestLocale
from app.core.pagination import MAX_PAGE
from app.core.rate_limit import (
    limiter,
)
from app.db.session import get_db
from app.models.models import (
    ChatMessage,
)
from app.schemas.trainer_api import (
    ChatMessageOut, MemberWeeklyFeedbackOut,
    ReportGoalsOut,
    ReportGoalsSaveRequest,
    ReportFeedbackOut,
    ReportFeedbackSaveRequest,
    MemberReportSendsOut,
    ReportQueueOut, ReportSendRequest, ReportSendsOut, ReportSummaryOut,
    WeeklyReportOut,
)
from app.services import (
    notification_service,
    trainer_report_summary_service,
    report_pdf_storage,
)
from app.services.trainer import chat as trainer_chat_service
from app.services.trainer import _common as trainer_common_service
from app.services.trainer import reports as trainer_reports_service
from app.services.trainer import weekly_feedback as trainer_weekly_feedback_service
from app.api.v1.trainer._common import (
    _audit_client_read,
    _is_ymd,
    _require_client,
)


router = APIRouter(tags=["trainer"])


# ---- 주간 리포트 (트레이너 → 회원) ----


def _report_week(day: str) -> _date:
    """리포트 주차를 검증해 그 주의 월요일로 정규화한다.

    아직 오지 않은 주는 거부한다 — 값이 전부 0 인 리포트를 만들어 회원에게
    보낼 수 있고, 화면에도 다음 주로 가는 길이 없다.
    """
    if not _is_ymd(day):
        raise HTTPException(status_code=422, detail="week_start 는 YYYY-MM-DD 형식이어야 합니다.")
    week = trainer_reports_service.week_start_of(_date.fromisoformat(day))
    today = _date.fromisoformat(trainer_common_service.today_iso())
    if week > trainer_reports_service.week_start_of(today):
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
    return trainer_reports_service.build_weekly_report(
        db, trainer.id, member_id, _report_week(week_start or trainer_common_service.today_iso())
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
        _report_week(week_start or trainer_common_service.today_iso()),
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
    return trainer_reports_service.get_report_feedback(
        db, trainer.id, member_id,
        _report_week(week_start or trainer_common_service.today_iso()),
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
    week = _report_week(payload.week_start or trainer_common_service.today_iso())
    return trainer_reports_service.save_report_feedback(
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
    return trainer_weekly_feedback_service.get_member_weekly_feedback(
        db, member_id, _report_week(week_start or trainer_common_service.today_iso())
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
    return trainer_reports_service.get_report_goals(
        db, member_id, _report_week(week_start or trainer_common_service.today_iso())
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
    week = _report_week(payload.week_start or trainer_common_service.today_iso())
    return trainer_reports_service.save_report_goals(
        db, trainer.id, member_id, week, payload.goals
    )


@router.get("/trainer/reports/queue", response_model=ReportQueueOut)
def trainer_report_queue(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    week_start: str | None = Query(None, description="YYYY-MM-DD (기본: 이번 주)"),
) -> ReportQueueOut:
    """리포트 작업대의 큐 — 담당 회원 전원의 그 주 요약을 한 번에. (#2863)

    작업대가 회원마다 리포트·회원 피드백을 따로 부르면 회원 N명에 요청 2N개가
    나갔다. 큐가 쓰는 값(세션 예약·완료, 이행률)만 묶어 준다 — 회원 한 명의
    전체 리포트는 편집기를 열 때 `/trainer/clients/{id}/report` 로 읽는다.
    """
    return trainer_reports_service.build_report_queue(
        db, trainer.id, _report_week(week_start or trainer_common_service.today_iso())
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
    return trainer_reports_service.list_report_sends(
        db, trainer.id, _report_week(week_start or trainer_common_service.today_iso())
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
    return trainer_reports_service.list_member_report_sends(
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
    week = _report_week(payload.week_start or trainer_common_service.today_iso())
    text = (payload.message or "").strip()
    if not text:
        report = trainer_reports_service.build_weekly_report(db, trainer.id, member_id, week)
        text = report.message
    return trainer_chat_service.send_message(
        db, trainer.id, member_id, "trainer", text,
        notify=notification_service.WEEKLY_REPORT,
        report_week_start=week.isoformat(),
    )


@router.post(
    "/trainer/clients/{member_id}/report/send-pdf",
    response_model=ChatMessageOut,
    status_code=201,
)
def trainer_send_report_pdf(
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

    동기 라우트다(#2835). 멱등 조회·PDF 저장(`os.fsync`)·메시지 커밋이 모두 동기라
    `async def` 로 두면 이벤트 루프를 막는다. 업로드도 `UploadFile.file` 로 읽는다.
    """
    _require_client(db, trainer.id, member_id)
    week = _report_week(week_start)
    text = message.strip()
    if not text:
        raise HTTPException(status_code=422, detail="리포트와 함께 보낼 메시지를 입력해 주세요.")

    # 재시도는 기존 메시지를 바로 돌려줘 파일을 다시 쓰지 않는다.
    if client_request_id:
        existing = trainer_chat_service.find_message_by_client_request(
            db, trainer.id, member_id, "trainer", client_request_id
        )
        if existing is not None:
            if existing.body != text or existing.attachment_type != "pdf":
                raise HTTPException(
                    status_code=409,
                    detail="같은 client_request_id에 다른 메시지를 보낼 수 없습니다.",
                )
            return trainer_chat_service.chat_message_out(existing, "trainer")

    if pdf.content_type != "application/pdf":
        raise HTTPException(status_code=415, detail="PDF 파일만 전송할 수 있습니다.")
    settings = get_settings()
    data = pdf.file.read(settings.max_report_pdf_bytes + 1)
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
        sent = trainer_chat_service.send_message(
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
    except trainer_common_service.IdempotencyConflict as exc:
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
