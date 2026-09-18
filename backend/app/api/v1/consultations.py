from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.api.deps import RequireMember
from app.core.pagination import DEFAULT_PAGE, MAX_PAGE, parse_before
from app.db.session import get_db
from app.schemas.consultation_api import ConsultationCreate, ConsultationOut
from app.schemas.reservation_api import TrainerSlotOut
from app.services import consultation_service, reservation_service

router = APIRouter(tags=["consultations"])

#: 고른 자리를 잡을 수 없을 때 409 본문의 `detail.code`. 대기 중복 409 와 가른다.
SLOT_UNAVAILABLE_CODE = "slot_unavailable"
#: 답을 기다리는 요청이 상한에 닿았을 때 409 본문의 `detail.code`. (#1628)
TOO_MANY_PENDING_CODE = "too_many_pending"
#: 24시간 신청 한도를 넘었을 때 429 본문의 `detail.code`. (#1628)
RATE_LIMITED_CODE = "consultation_rate_limited"


@router.post(
    "/consultations",
    response_model=ConsultationOut,
    status_code=status.HTTP_201_CREATED,
)
def create_consultation(
    payload: ConsultationCreate,
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> ConsultationOut:
    try:
        return consultation_service.create_consultation(db, member.id, payload)
    except consultation_service.InvalidConsultationRequest as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except consultation_service.ConsultationTargetNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except consultation_service.DuplicatePendingConsultation as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except consultation_service.TooManyPendingConsultations as exc:
        # 대기 중복 409 와 **구분되는 코드**를 싣는다. 앱이 둘을 섞으면 신청하지 않은
        # 트레이너를 "이미 대기 중" 으로 표시한다. (#1628)
        raise HTTPException(
            status_code=409,
            detail={
                "code": TOO_MANY_PENDING_CODE,
                "message": str(exc),
                "limit": exc.limit,
            },
        ) from exc
    except consultation_service.ConsultationRateLimited as exc:
        raise HTTPException(
            status_code=429,
            detail={
                "code": RATE_LIMITED_CODE,
                "message": str(exc),
                "limit": exc.limit,
            },
            headers={"Retry-After": str(exc.retry_after_seconds)},
        ) from exc
    except reservation_service.SlotNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except reservation_service.SlotUnavailable as exc:
        # 다른 회원이 먼저 고른 자리이거나, 목록을 띄워 둔 사이에 만료 하한을
        # 지난 자리다. 앱은 목록을 다시 읽어 남은 자리를 보여 준다. (#1873)
        #
        # 같은 409 인 "이미 대기 중인 요청" 과 **구분되는 코드**를 싣는다. 앱이 둘을
        # 섞으면 자리를 놓친 회원을 대기 중으로 잘못 표시해, 다른 자리로 다시
        # 신청하는 길까지 막는다.
        raise HTTPException(
            status_code=409,
            detail={"code": SLOT_UNAVAILABLE_CODE, "message": str(exc)},
        ) from exc


@router.get("/consultations/slots", response_model=list[TrainerSlotOut])
def consultation_slots(
    trainer_id: Annotated[str, Query(description="상담을 신청할 트레이너")],
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> list[TrainerSlotOut]:
    """상담 신청 폼이 보여 줄 그 트레이너의 빈 `1:1 PT` 자리. (#1873)

    헬스장 탭의 예약 가능 시간 목록(`GET /trainers/{id}/slots`)과 다른 점은 둘이다
    — 신청하는 순간 자리를 잠그므로 **트레이너가 확인할 틈이 남은 자리**만 주고
    (`CONSULT_SLOT_MIN_LEAD_HOURS`), 이미 잠긴 자리는 빼고 준다.

    비어 있으면 앱은 신청 버튼을 잠그고 헬스장 전화를 안내한다 — 없는 시간을
    지어내지 않는다.
    """
    return consultation_service.available_slots(db, trainer_id)


@router.get("/consultations/me", response_model=list[ConsultationOut])
def list_my_consultations(
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(
        DEFAULT_PAGE, ge=1, le=MAX_PAGE, description="한 번에 가져올 요청 수"
    ),
    before: str | None = Query(
        None, description="ISO datetime 커서(다음 쪽) — 받은 마지막 요청의 created_at"
    ),
    before_id: str | None = Query(
        None, description="복합 커서 tie-break — 받은 마지막 요청의 id"
    ),
) -> list[ConsultationOut]:
    """내가 보낸 상담 요청 한 쪽(최신순, 기본 50건). (#980)

    필터가 없어 승인·거절된 지난 요청까지 함께 자란다. 파라미터 없이 부르면 최신
    50건이고, 그보다 오래된 요청은 커서로 이어 받는다.
    """
    return consultation_service.list_my_consultations(
        db,
        member.id,
        limit=limit,
        before=parse_before(before),
        before_id=before_id,
    )


@router.get(
    "/consultations/{consultation_id}",
    response_model=ConsultationOut,
)
def get_my_consultation(
    consultation_id: str,
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> ConsultationOut:
    consultation = consultation_service.get_my_consultation(
        db, member.id, consultation_id
    )
    if consultation is None:
        raise HTTPException(status_code=404, detail="상담 요청을 찾을 수 없습니다.")
    return consultation


@router.delete(
    "/consultations/{consultation_id}",
    response_model=ConsultationOut,
)
def cancel_my_consultation(
    consultation_id: str,
    member: RequireMember,
    db: Annotated[Session, Depends(get_db)],
) -> ConsultationOut:
    try:
        return consultation_service.cancel_my_consultation(
            db, member.id, consultation_id
        )
    except consultation_service.ConsultationNotFound as exc:
        raise HTTPException(status_code=404, detail="상담 요청을 찾을 수 없습니다.") from exc
    except consultation_service.ConsultationNotCancellable as exc:
        raise HTTPException(
            status_code=409, detail="대기 중인 상담 요청만 취소할 수 있습니다."
        ) from exc
