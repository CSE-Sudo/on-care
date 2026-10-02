"""트레이너 도메인 — 고객 후속 관리 할 일. (#869)"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import (
    TrainerFollowUpTask, User,
)
from app.schemas.trainer_api import (
    TrainerFollowUpTaskOut,
)


# ---- 고객 후속 관리 할 일 (#869) ----
#
# 트레이너가 고객 상태를 보다 "며칠 뒤 다시 확인할 것"을 남겨 두는 최소 업무 큐다.
# 대시보드는 오늘 처리할 목록으로, 고객 상세는 그 고객의 미완료 목록으로 읽는다.


class FollowUpTaskNotFound(Exception):
    """그 트레이너에게 그 id 의 할 일이 없다(라우터가 404 로 변환)."""


#: 할 일 목록이 한 번에 내려주는 최대 건수. 완료한 항목까지 쌓이는 데이터라
#: 오래 쓴 계정에서 응답이 무한정 커지지 않게 자른다(메모 목록과 같은 이유).
_FOLLOW_UP_LIMIT = 100


def _follow_up_out(
    task: TrainerFollowUpTask, member_name: str = ""
) -> TrainerFollowUpTaskOut:
    return TrainerFollowUpTaskOut(
        id=task.id,
        member_id=task.member_id,
        member_name=member_name,
        title=task.title,
        due_date=task.due_date,
        status=task.status,
        context_type=task.context_type,
        created_at=task.created_at,
        updated_at=task.updated_at,
        completed_at=task.completed_at,
    )


def _follow_up_rows(
    db: Session,
    trainer_id: str,
    *,
    member_id: str | None = None,
    status: str | None = None,
    due_on_or_before: str | None = None,
) -> list[tuple[TrainerFollowUpTask, str]]:
    """할 일 행과 회원 이름을 함께 읽는다.

    이름을 붙여 내려주는 까닭은 대시보드가 "누구의 할 일인가"를 함께 보여 주기
    때문이다 — 화면이 할 일마다 회원을 다시 조회하면 목록 하나에 요청이 N 번 는다.

    정렬은 예정일 오름차순이다(지난 항목이 먼저 온다). 같은 날짜 안에서는 만든
    순서를 지키고, 같은 시각에 만들어진 둘은 id 로 tie-break 해 순서가 흔들리지
    않게 한다.
    """
    stmt = (
        select(TrainerFollowUpTask, User.name)
        .join(User, User.id == TrainerFollowUpTask.member_id)
        .where(TrainerFollowUpTask.trainer_id == trainer_id)
    )
    if member_id is not None:
        stmt = stmt.where(TrainerFollowUpTask.member_id == member_id)
    if status is not None:
        stmt = stmt.where(TrainerFollowUpTask.status == status)
    if due_on_or_before is not None:
        stmt = stmt.where(TrainerFollowUpTask.due_date <= due_on_or_before)
    stmt = stmt.order_by(
        TrainerFollowUpTask.due_date.asc(),
        TrainerFollowUpTask.created_at.asc(),
        TrainerFollowUpTask.id.asc(),
    ).limit(_FOLLOW_UP_LIMIT)
    return [(task, name or "") for task, name in db.execute(stmt).all()]


def build_client_follow_ups(
    db: Session, trainer_id: str, member_id: str, *, include_completed: bool = False
) -> list[TrainerFollowUpTaskOut]:
    """그 고객에 대해 내가 남긴 후속 관리 할 일(예정일 순).

    기본은 미완료만이다 — 고객 상세가 묻는 것은 "이 고객에게 남은 일이 무엇인가"
    이고, 완료 이력까지 섞으면 남은 일이 묻힌다.
    """
    rows = _follow_up_rows(
        db,
        trainer_id,
        member_id=member_id,
        status=None if include_completed else "pending",
    )
    return [_follow_up_out(task, name) for task, name in rows]


def build_due_follow_ups(db: Session, trainer_id: str) -> list[TrainerFollowUpTaskOut]:
    """오늘까지 처리해야 할 내 미완료 할 일.

    오늘 예정과 **기한이 지난** 미완료를 함께 돌려준다 — 지난 항목을 빼면 하루만
    지나도 화면에서 사라져, 놓치지 않으려고 만든 기능이 놓치는 경로가 된다.
    지난 항목이 예정일 오름차순의 앞에 오므로 화면이 따로 가르지 않아도 위에 쌓인다.
    """
    return [
        _follow_up_out(task, name)
        for task, name in _follow_up_rows(
            db, trainer_id, status="pending", due_on_or_before=clock.today_iso()
        )
    ]


def build_open_follow_ups(db: Session, trainer_id: str) -> list[TrainerFollowUpTaskOut]:
    """예정일과 무관하게 내 미완료 할 일 전체(예정일 순)."""
    return [
        _follow_up_out(task, name)
        for task, name in _follow_up_rows(db, trainer_id, status="pending")
    ]


def _find_follow_up_by_request(
    db: Session, trainer_id: str, client_request_id: str
) -> TrainerFollowUpTask | None:
    return db.scalar(
        select(TrainerFollowUpTask).where(
            TrainerFollowUpTask.trainer_id == trainer_id,
            TrainerFollowUpTask.client_request_id == client_request_id,
        )
    )


def create_follow_up(
    db: Session,
    trainer_id: str,
    member_id: str,
    *,
    title: str,
    due_date: str,
    context_type: str = "general",
    client_request_id: str | None = None,
) -> TrainerFollowUpTaskOut:
    """담당 고객에 대한 후속 관리 할 일을 등록한다.

    [client_request_id] 가 오면 그 시도에 대해 멱등하다 — 응답을 못 받고 재시도한
    등록이 같은 할 일을 두 번 만들지 않는다(스케줄 생성과 같은 규약).
    """
    if client_request_id:
        existing = _find_follow_up_by_request(db, trainer_id, client_request_id)
        if existing is not None:
            return _follow_up_out(existing, _member_name(db, existing.member_id))

    now = datetime.now(timezone.utc)
    task = TrainerFollowUpTask(
        id=f"followup-{uuid.uuid4().hex[:12]}",
        trainer_id=trainer_id,
        member_id=member_id,
        title=title,
        due_date=due_date,
        status="pending",
        context_type=context_type,
        client_request_id=client_request_id,
        created_at=now,
        updated_at=now,
    )
    db.add(task)
    # 같은 멱등키로 동시에 들어온 두 요청이 나란히 위 조회를 통과하면 유니크 제약이
    # 한쪽을 막는다. 그 충돌을 여기서 잡아 먼저 저장된 쪽을 돌려준다.
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        if client_request_id:
            existing = _find_follow_up_by_request(db, trainer_id, client_request_id)
            if existing is not None:
                return _follow_up_out(existing, _member_name(db, existing.member_id))
        raise
    db.commit()
    db.refresh(task)
    return _follow_up_out(task, _member_name(db, member_id))


def _member_name(db: Session, member_id: str) -> str:
    return db.scalar(select(User.name).where(User.id == member_id)) or ""


def _owned_follow_up(
    db: Session, trainer_id: str, task_id: str
) -> TrainerFollowUpTask:
    """내가 만든 할 일만 집는다.

    남의 할 일과 없는 할 일을 똑같이 다룬다 — 존재 여부를 드러내면 id 를 훑는
    것만으로 다른 트레이너의 업무가 있다는 사실을 알 수 있다(메모와 같은 규약).
    """
    task = db.scalar(
        select(TrainerFollowUpTask).where(
            TrainerFollowUpTask.id == task_id,
            TrainerFollowUpTask.trainer_id == trainer_id,
        )
    )
    if task is None:
        raise FollowUpTaskNotFound("할 일을 찾을 수 없습니다.")
    return task


def update_follow_up(
    db: Session, trainer_id: str, task_id: str, fields: dict
) -> TrainerFollowUpTaskOut:
    """할 일의 내용·예정일을 고친다. 상태는 완료 경로에서만 바뀐다."""
    task = _owned_follow_up(db, trainer_id, task_id)
    if "title" in fields:
        task.title = fields["title"]
    if "due_date" in fields:
        task.due_date = fields["due_date"]
    task.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(task)
    return _follow_up_out(task, _member_name(db, task.member_id))


def complete_follow_up(
    db: Session, trainer_id: str, task_id: str
) -> TrainerFollowUpTaskOut:
    """할 일을 완료로 넘긴다.

    이미 완료된 할 일에 같은 요청이 다시 와도 성공으로 돌려준다 — 대시보드에서
    두 번 눌렀거나 응답을 못 받고 재시도한 경우이고, 그때 409 를 주면 화면은
    이미 사라진 항목에 대해 오류를 띄운다. 완료 시각은 처음 한 번만 찍는다.
    """
    task = _owned_follow_up(db, trainer_id, task_id)
    if task.status != "completed":
        now = datetime.now(timezone.utc)
        task.status = "completed"
        task.completed_at = now
        task.updated_at = now
        db.commit()
        db.refresh(task)
    return _follow_up_out(task, _member_name(db, task.member_id))
