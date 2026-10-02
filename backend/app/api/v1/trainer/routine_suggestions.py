"""트레이너 라우터 — AI 개인운동 제안 검토. (#790)"""
from __future__ import annotations

from typing import Annotated

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
)
from sqlalchemy.orm import Session

from app.api.deps import RequireTrainer
from app.db.session import get_db
from app.schemas.trainer_api import (
    RoutineOut, RoutineSuggestionApproveRequest, RoutineSuggestionCreateRequest,
)
from app.services.trainer import routine_suggestions as trainer_routine_suggestions_service
from app.services.trainer import routines as trainer_routines_service
from app.api.v1.trainer._common import (
    _require_client,
)


router = APIRouter(tags=["trainer"])


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
    return trainer_routine_suggestions_service.list_routine_suggestions(db, trainer.id, member_id)


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
    return trainer_routine_suggestions_service.create_routine_suggestion(
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
        return trainer_routine_suggestions_service.approve_routine_suggestion(
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
    except trainer_routines_service.RoutineNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_routine_suggestions_service.RoutineAlreadyReviewed as exc:
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
        return trainer_routine_suggestions_service.dismiss_routine_suggestion(
            db, trainer.id, suggestion_id
        )
    except trainer_routines_service.RoutineNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_routine_suggestions_service.RoutineAlreadyReviewed as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
