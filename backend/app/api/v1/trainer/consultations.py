"""트레이너 라우터 — 상담 인박스. (#467)"""
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
from app.core.pagination import DEFAULT_PAGE, MAX_PAGE, parse_before
from app.db.session import get_db
from app.schemas.consultation_api import (
    ConsultationAccept,
    ConsultationAcceptOut,
    ConsultationDecision,
    ConsultationStatusFilter,
    TrainerConsultationOut,
)
from app.services import (
    consultation_service,
    trainer_service,
)


router = APIRouter(tags=["trainer"])


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
