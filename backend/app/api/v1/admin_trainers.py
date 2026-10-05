"""운영자 — 신고·계정 관리. (#3008)

트레이너 운영자 승인 절차는 없앴다(#3008). 트레이너는 가입하고 헬스장을 고르면 바로
활동한다. 대신 회원이 트레이너를 신고하고(`POST /trainers/{id}/reports`), 운영자가
트레이너 웹 `신고·계정 관리` 화면에서 신고를 처리하고 트레이너를 찾아 계정을
정지·해제한다(`account_suspension_service`).

모두 관리자 전용이다(비관리자 403, 미인증 401). 처리 결과는 감사 로그에 남긴다.
"""
from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session

from app.api.deps import RequireAdmin
from app.db.session import get_db
from app.schemas.admin_ops import (
    AdminReportCloseIn,
    AdminTrainerOut,
    AdminTrainerReportOut,
    AdminUserStatusOut,
)
from app.schemas.text_limits import TEXT_NAME_MAX
from app.services import (
    account_suspension_service,
    admin_trainer_service,
    trainer_report_service,
)
from app.services.audit import client_ip, record as audit

router = APIRouter(tags=["admin"])


@router.get("/admin/trainers", response_model=list[AdminTrainerOut])
def admin_list_trainers(
    admin: RequireAdmin,
    db: Annotated[Session, Depends(get_db)],
    q: str = Query("", max_length=TEXT_NAME_MAX),
    state: str = Query("all", pattern="^(all|active|suspended)$"),
) -> list[AdminTrainerOut]:
    """트레이너 검색·목록. 처리 전 신고가 많은 순, 그다음 최근 가입 순."""
    return admin_trainer_service.list_trainers(db, q=q, state=state)


@router.get("/admin/trainer-reports", response_model=list[AdminTrainerReportOut])
def admin_list_trainer_reports(
    admin: RequireAdmin,
    db: Annotated[Session, Depends(get_db)],
    status: str = Query("open", pattern="^(open|closed|all)$"),
) -> list[AdminTrainerReportOut]:
    """신고 목록 — 처리 전(기본)·처리됨·전체, 최근 순."""
    return trainer_report_service.list_reports(db, status=status)


@router.post(
    "/admin/trainer-reports/{report_id}/close",
    response_model=AdminTrainerReportOut,
)
def admin_close_trainer_report(
    report_id: str,
    payload: AdminReportCloseIn,
    request: Request,
    admin: RequireAdmin,
    db: Annotated[Session, Depends(get_db)],
) -> AdminTrainerReportOut:
    """신고 처리 — `resolved`(조치함) 또는 `dismissed`(조치 없이 넘김). 이미 처리한
    신고는 409."""
    try:
        out = trainer_report_service.close_report(
            db, report_id, outcome=payload.outcome, admin_id=admin.id
        )
    except trainer_report_service.ReportNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_report_service.ReportAlreadyClosed as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    audit(
        db,
        event="admin.trainer_report_close",
        user_id=admin.id,
        target_user_id=out.trainer_id,
        ip=client_ip(request),
        success=True,
        detail=f"{report_id}:{out.status}",
    )
    return out


@router.post(
    "/admin/users/{user_id}/suspend", response_model=AdminUserStatusOut
)
def admin_suspend_user(
    user_id: str,
    request: Request,
    admin: RequireAdmin,
    db: Annotated[Session, Depends(get_db)],
) -> AdminUserStatusOut:
    """계정 정지 — 즉시 로그아웃되고 다시 로그인할 수 없다.

    트레이너면 담당 관계를 모두 해제하고(회원에게 담당 해제 알림, 잡힌 PT 일정 취소)
    대기 중 담당 요청을 거둔다. 운영자 계정은 정지할 수 없다(409).
    """
    try:
        out = account_suspension_service.suspend(db, user_id, admin_id=admin.id)
    except account_suspension_service.UserNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except account_suspension_service.SuspensionNotAllowed as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    audit(
        db,
        event="admin.user_suspend",
        user_id=admin.id,
        target_user_id=user_id,
        ip=client_ip(request),
        success=True,
        detail=f"released={out.released_clients}",
    )
    return out


@router.post(
    "/admin/users/{user_id}/unsuspend", response_model=AdminUserStatusOut
)
def admin_unsuspend_user(
    user_id: str,
    request: Request,
    admin: RequireAdmin,
    db: Annotated[Session, Depends(get_db)],
) -> AdminUserStatusOut:
    """정지 해제 — 계정만 되살린다. 해제했던 담당 관계는 복구하지 않는다."""
    try:
        out = account_suspension_service.unsuspend(db, user_id)
    except account_suspension_service.UserNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    audit(
        db,
        event="admin.user_unsuspend",
        user_id=admin.id,
        target_user_id=user_id,
        ip=client_ip(request),
        success=True,
    )
    return out
