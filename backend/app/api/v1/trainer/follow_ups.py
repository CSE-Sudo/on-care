"""트레이너 라우터 — 고객 후속 관리 할 일. (#869)"""
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
from app.db.session import get_db
from app.schemas.trainer_api import (
    FollowUpScope,
    TrainerFollowUpTaskCreateRequest, TrainerFollowUpTaskOut,
    TrainerFollowUpTaskUpdateRequest,
)
from app.services import (
    trainer_service,
)
from app.api.v1.trainer._common import (
    _require_client,
)


router = APIRouter(tags=["trainer"])


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
