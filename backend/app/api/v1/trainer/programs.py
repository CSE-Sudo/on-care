"""트레이너 라우터 — 프로그램 초안(#708)과 프로그램 템플릿(#920)."""
from __future__ import annotations

from typing import Annotated

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query,
)
from sqlalchemy.orm import Session

from app.api.deps import RequireTrainer
from app.api.v1.trainer._common import _require_client
from app.db.session import get_db
from app.schemas.trainer_api import (
    TrainerProgramDraftCreate, TrainerProgramDraftOut,
    TrainerProgramDraftSummary, TrainerProgramDraftUpdate,
    TrainerProgramTemplateCreate, TrainerProgramTemplateOut,
    TrainerProgramTemplateUpdate,
)
from app.services import (
    trainer_program_template_service,
)
from app.services.trainer import programs as trainer_programs_service


router = APIRouter(tags=["trainer"])


# ---- 프로그램 초안 (#708) ----
#
# 초안은 트레이너의 것이라 회원 경로 아래가 아니다. 소유권 경계는 trainer_id 이고,
# 남의 초안과 없는 초안은 똑같이 404 다.


@router.get("/trainer/programs", response_model=list[TrainerProgramDraftSummary])
def trainer_program_drafts(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
    member_id: str | None = Query(
        None,
        min_length=1,
        max_length=64,
        description="이 회원에게 자동 보관한 초안만(#2873)",
    ),
) -> list[TrainerProgramDraftSummary]:
    """내가 저장한 프로그램 초안 목록(최근 수정 먼저, 운동 구성 제외).

    `member_id` 를 주면 코칭 화면이 그 회원에게 자동 보관한 것만 돌려준다
    (#2873). 내 초안만 거르므로 남의 회원 id 로는 빈 목록이다.
    """
    return trainer_programs_service.build_program_drafts(
        db, trainer.id, member_id=member_id
    )


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
    """프로그램 초안 저장. 세션이 여러 개여도, 비어 있어도 저장된다.

    `member_id` 를 주면 코칭 화면의 자동 보관이다(#2873) — 살아 있는 담당
    회원이 아니면 다른 회원 경로와 같은 404 다.
    """
    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="프로그램 이름이 필요합니다.")
    if payload.member_id is not None:
        _require_client(db, trainer.id, payload.member_id)
    return trainer_programs_service.create_program_draft(
        db, trainer.id,
        name=name,
        goal=payload.goal.strip(),
        period=payload.period.strip(),
        memo=payload.memo,
        sessions=payload.sessions,
        member_id=payload.member_id,
        workspace=payload.workspace,
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
        return trainer_programs_service.get_program_draft(db, trainer.id, draft_id)
    except trainer_programs_service.ProgramDraftNotFound as exc:
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
        return trainer_programs_service.update_program_draft(
            db, trainer.id, draft_id, fields
        )
    except trainer_programs_service.ProgramDraftNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.delete("/trainer/programs/{draft_id}")
def trainer_delete_program_draft(
    draft_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """저장된 초안 삭제. 이미 배정한 루틴·등록한 일정은 그대로 남는다."""
    try:
        trainer_programs_service.delete_program_draft(db, trainer.id, draft_id)
    except trainer_programs_service.ProgramDraftNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"status": "deleted"}


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
