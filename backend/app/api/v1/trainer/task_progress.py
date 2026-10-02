"""트레이너 라우터 — 대시보드 오늘 할 일 진행 상태."""
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
    TrainerTaskKeyChange,
    TrainerTaskProgressDayOut, TrainerTaskProgressOut, TrainerTaskProgressSave,
)
from app.services import (
    trainer_task_progress_service,
)
from app.api.v1.trainer._common import (
    _is_ymd,
)


router = APIRouter(tags=["trainer"])


@router.get("/trainer/dashboard/task-progress", response_model=TrainerTaskProgressOut)
def trainer_task_progress(
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerTaskProgressOut:
    """오늘 할 일 진행 상태 — 보관 기간 안의 날짜별 기록. (#1633)

    기기 로컬이 아니라 계정 단위다. 센터 PC 에서 체크한 항목이 태블릿에서도
    체크돼 있어야 한다.
    """
    return trainer_task_progress_service.build_progress(db, trainer.id)


@router.put(
    "/trainer/dashboard/task-progress/{day}",
    response_model=TrainerTaskProgressDayOut,
)
def trainer_save_task_progress(
    day: str,
    payload: TrainerTaskProgressSave,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerTaskProgressDayOut:
    """그날의 진행 상태를 통째로 저장한다. KST 오늘·어제만 받는다."""
    if not _is_ymd(day):
        raise HTTPException(status_code=422, detail="날짜는 YYYY-MM-DD 형식이어야 합니다.")
    if day not in trainer_task_progress_service.writable_dates():
        raise HTTPException(
            status_code=422, detail="오늘 또는 어제(KST)만 저장할 수 있습니다."
        )
    return trainer_task_progress_service.save_day(db, trainer.id, day, payload)


@router.post(
    "/trainer/dashboard/task-progress/{day}/keys",
    response_model=TrainerTaskProgressDayOut,
)
def trainer_change_task_key(
    day: str,
    payload: TrainerTaskKeyChange,
    trainer: RequireTrainer,
    db: Annotated[Session, Depends(get_db)],
) -> TrainerTaskProgressDayOut:
    """할 일 키 하나를 체크·해제·삭제한다. KST 오늘·어제만 받는다. (#2886)

    그날 전체를 덮어쓰지 않아, 다른 탭·기기에서 체크한 할 일이 남는다. 응답은
    반영 뒤의 그날 상태라 앱이 다른 기기의 변경까지 받아 그린다.
    """
    if not _is_ymd(day):
        raise HTTPException(status_code=422, detail="날짜는 YYYY-MM-DD 형식이어야 합니다.")
    if day not in trainer_task_progress_service.writable_dates():
        raise HTTPException(
            status_code=422, detail="오늘 또는 어제(KST)만 저장할 수 있습니다."
        )
    return trainer_task_progress_service.apply_key(db, trainer.id, day, payload)
