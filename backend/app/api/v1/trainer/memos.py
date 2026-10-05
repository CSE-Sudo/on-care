"""트레이너 라우터 — 회원별 트레이너 메모. (#706)"""
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
    ClientFeedbackOut, TrainerMemoCreateRequest, TrainerMemoOut, TrainerMemoUpdateRequest,
)
from app.services import (
    client_feedback_service,
)
from app.services.trainer import memos as trainer_memos_service
from app.services.trainer import routines as trainer_routines_service
from app.api.v1.trainer._common import (
    _audit_client_read,
    _require_client,
)


router = APIRouter(tags=["trainer"])


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
    return trainer_memos_service.build_memos(db, trainer.id, member_id)


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
        return trainer_memos_service.create_memo(
            db, trainer.id, member_id,
            body=body,
            source=payload.source,
            insight_id=payload.insight_id,
            insight_kind=payload.insight_kind,
            ref_id=payload.ref_id,
            ref_date=payload.ref_date,
            ref_kind=payload.ref_kind,
            category=payload.category,
        )
    except trainer_routines_service.RoutineNotFound as exc:
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
        return trainer_memos_service.update_memo(
            db, trainer.id, member_id, memo_id, fields
        )
    except trainer_memos_service.MemoNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_memos_service.MemoCategoryLocked as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get(
    "/trainer/clients/{member_id}/feedbacks",
    response_model=list[ClientFeedbackOut],
    dependencies=[_audit_client_read("report")],
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

    회원 주간 피드백의 통증 부위·컨디션이 실려, 같은 데이터를 주는
    `report/member-feedback` 과 같은 `report` 열람으로 남긴다(#2830, #3239).
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
        trainer_memos_service.delete_memo(db, trainer.id, member_id, memo_id)
    except trainer_memos_service.MemoNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"status": "deleted"}
