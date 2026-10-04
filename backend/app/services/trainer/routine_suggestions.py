"""트레이너 도메인 — AI 개인운동 제안 검토. (#790)"""
from __future__ import annotations

import json
import uuid
from collections.abc import Sequence

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import (
    TrainerRoutine,
)
from app.schemas.trainer_api import (
    RoutineOut,
)
from app.services import (
    notification_service,
    notification_templates,
    routine_suggestion_service,
)
from app.services.trainer._common import (
    ROUTINE_APPROVED,
    ROUTINE_DISMISSED,
    ROUTINE_PENDING,
    _apply_routine_duration,
    _routine_notification_args,
    _routine_out,
    _routine_outs,
    has_active_client_link,
)
from app.services.trainer.chat import (
    post_routine_delivery,
)
from app.services.trainer.routines import (
    RoutineNotFound,
    find_routine_by_client_request,
)


# ─────────────────────────────────── AI 개인운동 제안 검토 ───────────────────


class RoutineAlreadyReviewed(Exception):
    """이미 승인/거절된 제안을 다시 검토하려 했다."""


def create_routine_suggestion(
    db: Session,
    trainer_id: str,
    member_id: str,
    *,
    name: str,
    minutes: int,
    type_: str,
    reason: str,
    duration_seconds: int | None = None,
    sets: int | None = None,
    reps: int | None = None,
    hold_seconds: int | None = None,
    weight: float | None = None,
    evidence: Sequence[str] | None = None,
    client_request_id: str | None = None,
) -> RoutineOut:
    """AI 개인운동 후보를 검토 대기(pending) 로 만든다.

    [assign_routine] 과 나눠 둔 이유: 배정은 회원에게 곧바로 닿는 행동이고 알림도
    나가지만, 후보는 아직 아무에게도 닿지 않는다. 알림은 승인 시점에 나간다 —
    트레이너가 보지도 않은 운동으로 회원이 먼저 알림을 받으면 안 된다(#790).
    """
    if client_request_id:
        existing = find_routine_by_client_request(
            db, trainer_id, member_id, client_request_id
        )
        if existing is not None:
            return _routine_out(db, existing)

    max_order = db.scalar(
        select(func.max(TrainerRoutine.sort_order)).where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
        )
    )
    rt = TrainerRoutine(
        id=f"rt-{uuid.uuid4().hex[:12]}",
        trainer_id=trainer_id,
        member_id=member_id,
        name=name,
        minutes=minutes,
        # 시·분·초로 적은 시간(#2547). 근력은 세트로 잰다.
        duration_seconds=duration_seconds if type_ != "근력" else None,
        type=type_,
        # 세트·횟수·중량은 근력에만 남긴다 — 배정([assign_routine])과 같은
        # 규칙이다. 승인하면 이 행이 그대로 배정이 되므로 여기서 규칙이 갈리면
        # 승인 전후로 값이 달라진다. (#1321)
        sets=sets if type_ == "근력" else None,
        # 버티는 운동이면 초가 맞고 횟수는 비운다 — 한 세트를 두 단위로 적지
        # 않는다(#1969).
        reps=reps if type_ == "근력" and hold_seconds is None else None,
        hold_seconds=hold_seconds if type_ == "근력" else None,
        weight=round(weight, 1) if weight is not None and type_ == "근력" else None,
        reason=reason,
        source="ai",
        status=ROUTINE_PENDING,
        sort_order=(max_order or 0) + 1,
        evidence_json=json.dumps(list(evidence or []), ensure_ascii=False),
        client_request_id=client_request_id,
        created_at=clock.now(),
    )
    db.add(rt)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        if client_request_id:
            existing = find_routine_by_client_request(
                db, trainer_id, member_id, client_request_id
            )
            if existing is not None:
                return _routine_out(db, existing)
        raise
    db.commit()
    db.refresh(rt)
    return _routine_out(db, rt)


def list_routine_suggestions(
    db: Session, trainer_id: str, member_id: str
) -> list[RoutineOut]:
    """검토를 기다리는 AI 개인운동 제안. 승인·거절한 것은 빠진다.

    조회 자리에서 그날 후보를 준비한다(`routine_suggestion_service`). 트레이너가
    회원을 골라 생성을 요청해야만 후보가 생기면 관리 부담이 줄지 않는다 — AI 가
    먼저 준비하고 트레이너는 판단만 하는 것이 이 기능의 요구다(#790). 회원 조회가
    자동 추천을 준비하는 것(`build_member_routines`)과 같은 방식이다.
    """
    routine_suggestion_service.ensure_suggestions(db, trainer_id, member_id)
    rows = db.scalars(
        select(TrainerRoutine)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
            TrainerRoutine.status == ROUTINE_PENDING,
        )
        .order_by(TrainerRoutine.sort_order, TrainerRoutine.created_at)
    ).all()
    return _routine_outs(db, rows)


def _pending_suggestion(
    db: Session, trainer_id: str, suggestion_id: str
) -> TrainerRoutine:
    """검토할 수 있는 제안 하나. 남의 것·없는 것은 [RoutineNotFound].

    이미 처리된 제안은 [RoutineAlreadyReviewed] 로 나눈다 — 없는 것과 같은 답을
    주면, 두 번 눌렀을 때 트레이너가 "사라졌다" 로 읽는다. 실제로는 이미 반영됐다.
    """
    row = db.scalar(
        select(TrainerRoutine).where(
            TrainerRoutine.id == suggestion_id,
            TrainerRoutine.trainer_id == trainer_id,
        )
    )
    if row is None:
        raise RoutineNotFound("제안을 찾을 수 없습니다.")
    if row.status != ROUTINE_PENDING:
        raise RoutineAlreadyReviewed("이미 검토한 제안입니다.")
    return row


def approve_routine_suggestion(
    db: Session,
    trainer_id: str,
    suggestion_id: str,
    *,
    name: str | None = None,
    minutes: int | None = None,
    duration_seconds: int | None = None,
    type_: str | None = None,
    sets: int | None = None,
    reps: int | None = None,
    hold_seconds: int | None = None,
    weight: float | None = None,
    reason: str | None = None,
) -> RoutineOut:
    """제안을 승인해 회원에게 배정한다. 준 값이 있으면 그것으로 고쳐서 승인한다.

    새 행을 만들지 않고 이 행의 상태를 바꾼다. 후보와 배정이 같은 행이라
    회원 조회·완료 처리·프로그램 묶음이 지금 쓰는 경로를 그대로 지난다.
    """
    row = _pending_suggestion(db, trainer_id, suggestion_id)
    # 후보가 남아 있어도 담당이 해제된 회원에게는 배정·알림을 보내지 않는다. (#2281)
    if not has_active_client_link(db, trainer_id, row.member_id):
        raise RoutineNotFound("담당 회원을 찾을 수 없습니다.")
    if name is not None:
        row.name = name
    if type_ is not None:
        row.type = type_
    if reason is not None:
        row.reason = reason
    # 분·초는 루틴 수정과 같은 규칙으로 맞춘다 — 유형을 먼저 반영해야 근력으로
    # 바꿔 승인할 때 초가 남지 않는다. (#2547)
    _apply_routine_duration(row, minutes=minutes, duration_seconds=duration_seconds)
    if sets is not None:
        row.sets = sets
    if reps is not None:
        row.reps = reps
    if hold_seconds is not None:
        row.hold_seconds = hold_seconds
    if weight is not None:
        row.weight = round(weight, 1)
    # 유형을 근력이 아닌 것으로 바꿔 승인하면 세트·횟수·중량을 지운다 — 남겨
    # 두면 유산소 배정이 세트를 들고 회원에게 간다. 판단 기준은 **고친 뒤의**
    # 유형이다. (#1321)
    if row.type != "근력":
        row.sets = None
        row.reps = None
        row.hold_seconds = None
        row.weight = None
    elif row.hold_seconds is not None:
        # 버티는 운동으로 승인하면 횟수를 지운다. (#1969)
        row.reps = None
    row.status = ROUTINE_APPROVED
    row.reviewed_at = clock.now()
    row.reviewed_by = trainer_id
    # 회원 목록에는 승인한 날부터 걸린다 — 후보로 기다린 날들에는 회원이 받은
    # 적이 없다(#2161).
    row.active_from = clock.today_iso()

    # 알림은 여기서 나간다 — 회원이 볼 수 있게 된 시점이 곧 알릴 시점이다.
    notification_service.queue(
        db,
        member_id=row.member_id,
        kind=notification_service.EXERCISE,
        category=notification_service.MEMBER_ROUTINE,
        template=notification_templates.MEMBER_ROUTINE_ASSIGNED,
        template_args=_routine_notification_args(
            row.name, row.type, minutes=row.minutes,
            duration_seconds=row.duration_seconds,
            sets=row.sets, reps=row.reps, hold_seconds=row.hold_seconds,
            weight=row.weight,
        ),
    )
    # 채팅에도 남긴다(#2672) — 알림은 지나가지만 대화는 남는 기록이다.
    post_routine_delivery(
        db, trainer_id, row.member_id, kind="routine", routine_names=[row.name]
    )
    db.commit()
    db.refresh(row)
    return _routine_out(db, row)


def dismiss_routine_suggestion(
    db: Session, trainer_id: str, suggestion_id: str
) -> RoutineOut:
    """제안을 추천하지 않기로 한다. 회원 배정도 알림도 만들지 않는다."""
    row = _pending_suggestion(db, trainer_id, suggestion_id)
    row.status = ROUTINE_DISMISSED
    row.reviewed_at = clock.now()
    row.reviewed_by = trainer_id
    db.commit()
    db.refresh(row)
    return _routine_out(db, row)
