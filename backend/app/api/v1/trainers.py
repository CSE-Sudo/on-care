"""트레이너 디렉터리 라우터 — 회원앱 트레이너 찾기/상세/추천. (#324)

`/trainer/*`(단수)는 트레이너 앱이 자기 데이터를 다루는 곳이고, 여기 `/trainers`
(복수)는 회원이 트레이너를 **탐색**하는 디렉터리다. 쓰기는 신고(#3008) 하나뿐이다.
"""
from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status

from sqlalchemy.orm import Session

from app.api.deps import CurrentUser, RequireMember
from app.db.session import get_db
from app.schemas.admin_ops import TrainerReportCreate, TrainerReportOut
from app.schemas.gym_api import TrainerOut
from app.services import gym_service, trainer_report_service

router = APIRouter(tags=["trainers"])


@router.get("/trainers", response_model=list[TrainerOut])
def list_trainers(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> list[TrainerOut]:
    """전체 트레이너 디렉터리 — "트레이너 찾기" 목록."""
    return gym_service.list_trainers(db)


@router.get("/trainers/recommended", response_model=list[TrainerOut])
def list_recommended_trainers(
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> list[TrainerOut]:
    """홈·운동 탭의 추천 레일 — 회원의 목표·거리에 맞춰 줄 세운다. (#500)

    신호가 없는 회원(온보딩 전 등)은 운영자가 사유를 적어 둔 트레이너만 기존
    순서로 받는다.

    `/trainers/{trainer_id}` 보다 먼저 선언해야 "recommended" 가 id 로 잡히지 않는다.
    """
    return gym_service.list_recommended_trainers(db, current_user.id)


@router.get("/trainers/{trainer_id}", response_model=TrainerOut)
def get_trainer(
    trainer_id: str,
    current_user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerOut:
    """트레이너 상세.

    요청자를 넘기는 이유는 **내 담당 트레이너**만 소속 조건에서 빼기 위해서다(#691).
    """
    trainer = gym_service.get_trainer(db, trainer_id, viewer_id=current_user.id)
    if trainer is None:
        raise HTTPException(status_code=404, detail="트레이너를 찾을 수 없어요.")
    return trainer


@router.post(
    "/trainers/{trainer_id}/reports",
    response_model=TrainerReportOut,
    status_code=status.HTTP_201_CREATED,
)
def report_trainer(
    trainer_id: str,
    payload: TrainerReportCreate,
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerReportOut:
    """트레이너 신고(#3008) — 사칭·부적절한 메시지·기타.

    운영자가 트레이너 웹 `신고·계정 관리` 화면에서 보고 처리한다. 같은 트레이너를
    처리 전에 다시 신고하면 409 `report_already_open`.
    """
    try:
        return trainer_report_service.create_report(
            db, reporter_id=member.id, trainer_id=trainer_id, payload=payload
        )
    except trainer_report_service.TrainerNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except trainer_report_service.ReportAlreadyOpen as exc:
        raise HTTPException(
            status_code=409,
            detail={
                "code": trainer_report_service.ALREADY_OPEN_CODE,
                "message": str(exc),
            },
        ) from exc
