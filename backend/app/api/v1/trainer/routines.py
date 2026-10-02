"""트레이너 라우터 — 루틴 배정(트레이너/AI → 회원)과 루틴 선택지."""
from __future__ import annotations

from typing import Annotated

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
)
from sqlalchemy.orm import Session

from app.api.deps import RequireTrainer
from app.core.config import get_settings
from app.core.rate_limit import (
    rate_limit,
)
from app.db.session import get_db
from app.schemas.trainer_api import (
    DeliveryOut,
    RoutineAssignRequest, RoutineOut, ProgramAssignRequest, RoutineOptionsOut, RoutineOptionsRequest, RoutineUpdateRequest,
)
from app.services import (
    trainer_routine_options_service,
)
from app.services.trainer import routines as trainer_routines_service
from app.services.trainer import schedule as trainer_schedule_service
from app.api.v1.trainer._common import (
    _require_client,
)


router = APIRouter(tags=["trainer"])


# ---- 루틴 배정 (트레이너/AI → 회원) ----


@router.get(
    "/trainer/clients/{member_id}/deliveries/latest",
    response_model=DeliveryOut | None,
)
def trainer_latest_delivery(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> DeliveryOut | None:
    """이 회원에게 가장 최근에 보낸 것 한 묶음. (#2225)

    전송 이력이 PT 프로그램과 개인운동을 따로 나열하면, PT 완료 때 함께 보낸
    개인운동이 어느 PT 와 짝인지 알 수 없다(#2224). 보낸 적이 없으면 `null`.
    """
    _require_client(db, trainer.id, member_id)
    return trainer_schedule_service.latest_delivery(db, trainer.id, member_id)


@router.get(
    "/trainer/clients/{member_id}/routines/unsent",
    response_model=list[RoutineOut],
)
def trainer_unsent_personal_routines(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[RoutineOut]:
    """PT 에 붙여만 두고 아직 보내지 않은 개인운동. (#2225)

    지금은 그 사실이 스케줄 탭의 그 일정을 열어야만 보인다. 각 줄의
    `schedule_id` 로 어느 PT 의 것인지 알 수 있고, 보내는 것은 그 일정의
    `POST /trainer/schedule/{id}/routines/send` 가 맡는다(#2224).
    """
    _require_client(db, trainer.id, member_id)
    return trainer_schedule_service.unsent_personal_routines(db, trainer.id, member_id)


@router.get("/trainer/clients/{member_id}/routines", response_model=list[RoutineOut])
def trainer_client_routines(
    member_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[RoutineOut]:
    """담당 고객에게 배정된 루틴 목록."""
    _require_client(db, trainer.id, member_id)
    return trainer_routines_service.build_routines(db, member_id, trainer.id)


@router.post("/trainer/clients/{member_id}/routines", response_model=RoutineOut, status_code=201)
def trainer_assign_routine(
    member_id: str,
    payload: RoutineAssignRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> RoutineOut:
    """담당 고객에게 루틴 배정(트레이너 직접 또는 AI 추천)."""
    _require_client(db, trainer.id, member_id)
    # type/source/길이·범위는 RoutineAssignRequest(Field/Literal)가 이미 422 로 거른다.
    # 공백만 있는 이름은 trim 후 400.
    if not payload.name.strip():
        raise HTTPException(status_code=400, detail="루틴 이름이 필요합니다.")
    return trainer_routines_service.assign_routine(
        db, trainer.id, member_id,
        name=payload.name.strip(), minutes=payload.minutes,
        duration_seconds=payload.duration_seconds,
        type_=payload.type, reason=payload.reason, source=payload.source,
        client_request_id=payload.client_request_id,
        exercise_date=payload.exercise_date,
        intensity=payload.intensity,
        sets=payload.sets,
        reps=payload.reps,
        hold_seconds=payload.hold_seconds,
        weight=payload.weight,
    )


@router.post(
    "/trainer/clients/{member_id}/program",
    response_model=list[RoutineOut],
    status_code=201,
)
def trainer_assign_program(
    member_id: str,
    payload: ProgramAssignRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> list[RoutineOut]:
    """다중 세션 프로그램을 담당 고객에게 배정한다. 세션 하나가 루틴 한 건. (#709)

    세션이 하나뿐이면 결과가 단일 배정(`POST .../routines`)과 같은 모양이라,
    회원 화면에 없던 세션 라벨이 생기지 않는다. `client_request_id` 는 프로그램
    전체에 대해 멱등하다.
    """
    _require_client(db, trainer.id, member_id)
    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="프로그램 이름이 필요합니다.")
    if not any(session.exercises for session in payload.sessions):
        # 운동이 하나도 없는 프로그램을 배정하면 회원에게 빈 루틴만 간다.
        raise HTTPException(status_code=400, detail="운동이 하나 이상 필요합니다.")
    return trainer_routines_service.assign_program(
        db, trainer.id, member_id,
        name=name,
        sessions=payload.sessions,
        client_request_id=payload.client_request_id,
        delivery_kind=payload.delivery_kind,
        trainer_message=payload.trainer_message.strip(),
        start_date=payload.start_date,
        active_days=payload.active_days,
        suggestion_ids=payload.suggestion_ids,
    )


@router.put(
    "/trainer/clients/{member_id}/routines/{routine_id}",
    response_model=RoutineOut,
)
def trainer_update_routine(
    member_id: str,
    routine_id: str,
    payload: RoutineUpdateRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> RoutineOut:
    """배정한 루틴 수정(부분). 이름·시간(분 또는 초)·종류·사유만 바뀐다. (#504, #2547)

    남의 배정과 없는 루틴은 똑같이 404 다 — 존재 여부를 드러내지 않는다.
    """
    _require_client(db, trainer.id, member_id)
    fields = payload.model_dump(exclude_unset=True)
    if not fields:
        # 빈 PUT 을 성공으로 처리하면 클라이언트가 저장됐다고 오해한다.
        raise HTTPException(status_code=400, detail="수정할 항목이 없습니다.")
    if "name" in fields and not fields["name"].strip():
        raise HTTPException(status_code=400, detail="루틴 이름이 필요합니다.")
    if "name" in fields:
        fields["name"] = fields["name"].strip()
    try:
        return trainer_routines_service.update_routine(
            db, trainer.id, member_id, routine_id, fields
        )
    except trainer_routines_service.RoutineNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.delete("/trainer/clients/{member_id}/routines/{routine_id}")
def trainer_delete_routine(
    member_id: str,
    routine_id: str,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> dict:
    """배정한 루틴 철회. 회원 앱에서도 사라진다. (#504)"""
    _require_client(db, trainer.id, member_id)
    try:
        trainer_routines_service.delete_routine(db, trainer.id, member_id, routine_id)
    except trainer_routines_service.RoutineNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"status": "deleted"}


@router.post(
    "/trainer/clients/{member_id}/routine-options",
    response_model=RoutineOptionsOut,
    # LLM 을 부르는 엔드포인트라 /ai-coach/chat 과 같은 가드를 건다. 생성이
    # 실패해 규칙형으로 폴백해도 공급자 호출 비용은 이미 나간 뒤이므로,
    # 연타가 그대로 청구되지 않게 앞에서 막는다.
    dependencies=[
        Depends(
            rate_limit("routine-options", get_settings().routine_options_per_minute)
        )
    ],
)
def trainer_routine_options(
    member_id: str,
    payload: RoutineOptionsRequest,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> RoutineOptionsOut:
    """회원 실데이터를 LLM에 전달해 두 개의 맞춤 루틴 후보를 생성한다.

    설정된 AI 공급자를 사용할 수 없거나 응답 계약이 잘못되면 동일 응답 형태의
    규칙 기반 후보로 폴백한다.
    """
    _require_client(db, trainer.id, member_id)
    return trainer_routine_options_service.generate_routine_options(
        db,
        trainer.id,
        member_id,
        payload,
    )
