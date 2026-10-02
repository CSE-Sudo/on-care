"""운영자 — 트레이너 승인·반려. (#2825)

공개 가입으로 생긴 트레이너는 승인 전까지 회원 앱 디렉터리·상담 대상·담당 요청·
연결 코드에서 빠진다(`trainer_verification_service`). 운영자는 여기서 대기 목록을
보고 승인하거나 반려한다. 관리 화면은 아직 없다 — 엔드포인트만 둔다.

모두 관리자 전용이다(비관리자 403, 미인증 401). 처리 결과는 감사 로그에 남긴다.
"""
from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session

from app.api.deps import RequireAdmin
from app.db.session import get_db
from app.schemas.trainer_verification import (
    AdminTrainerVerificationOut,
    TrainerRejectIn,
)
from app.services import trainer_verification_service
from app.services.audit import client_ip, record as audit

router = APIRouter(tags=["admin"])


@router.get(
    "/admin/trainers", response_model=list[AdminTrainerVerificationOut]
)
def admin_list_trainers(
    admin: RequireAdmin,
    db: Annotated[Session, Depends(get_db)],
    status: str = Query(
        trainer_verification_service.PENDING,
        pattern="^(pending|approved|rejected|all)$",
    ),
) -> list[AdminTrainerVerificationOut]:
    """승인 대기(기본)·승인·반려·전체 트레이너."""
    return trainer_verification_service.list_for_review(db, status=status)


@router.post(
    "/admin/trainers/{trainer_id}/approve",
    response_model=AdminTrainerVerificationOut,
)
def admin_approve_trainer(
    trainer_id: str,
    request: Request,
    admin: RequireAdmin,
    db: Annotated[Session, Depends(get_db)],
) -> AdminTrainerVerificationOut:
    """승인 — 이때부터 회원 앱에 노출되고 상담·연결을 받을 수 있다."""
    try:
        out = trainer_verification_service.approve(db, trainer_id, admin_id=admin.id)
    except trainer_verification_service.TrainerNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    audit(
        db,
        event="admin.trainer_approve",
        user_id=admin.id,
        ip=client_ip(request),
        success=True,
        detail=trainer_id,
    )
    return out


@router.post(
    "/admin/trainers/{trainer_id}/reject",
    response_model=AdminTrainerVerificationOut,
)
def admin_reject_trainer(
    trainer_id: str,
    request: Request,
    admin: RequireAdmin,
    db: Annotated[Session, Depends(get_db)],
    payload: TrainerRejectIn | None = None,
) -> AdminTrainerVerificationOut:
    """반려 — 회원 앱에서 빠지고 새 상담·연결을 받을 수 없다. 사유는 트레이너 웹에 보인다."""
    try:
        out = trainer_verification_service.reject(
            db,
            trainer_id,
            admin_id=admin.id,
            reason=payload.reason if payload else "",
        )
    except trainer_verification_service.TrainerNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    audit(
        db,
        event="admin.trainer_reject",
        user_id=admin.id,
        ip=client_ip(request),
        success=True,
        detail=trainer_id,
    )
    return out
