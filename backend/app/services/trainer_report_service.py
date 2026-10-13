"""회원의 트레이너 신고와 운영자의 신고 처리. (#3008)

트레이너 운영자 승인 절차를 없앴다. 트레이너는 가입하고 실재하는 헬스장을 고르면
바로 회원 앱에 나온다. 소속을 사칭하거나 부적절한 메시지를 보내는 계정은 회원이
신고하고, 운영자가 트레이너 웹 `신고·계정 관리` 화면에서 신고를 보고 처리한다.
조치가 필요하면 계정을 정지한다(`account_suspension_service`).

- 같은 회원이 같은 트레이너를 처리 전(open)에 다시 신고하면 409 다. 한 사람이 같은
  신고를 여러 번 쌓아 목록을 부풀리지 못하게 한다. 처리된 뒤 다시 신고하는 것은 된다.
- 신고 목록에는 신고한 회원을 싣지 않는다. 처리에는 대상과 사유면 충분하다.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.models import TrainerReport, User
from app.schemas.admin_ops import (
    AdminTrainerReportOut,
    TrainerReportCreate,
    TrainerReportOut,
)

OPEN = "open"
RESOLVED = "resolved"
DISMISSED = "dismissed"

#: 같은 트레이너를 처리 전에 다시 신고했을 때의 `detail.code`.
ALREADY_OPEN_CODE = "report_already_open"

#: 운영 화면이 한 번에 읽는 신고 수. 오래된 처리 건은 잘린다.
LIST_LIMIT = 200


class TrainerNotFound(Exception):
    """신고할 트레이너가 없다 — 404."""


class ReportAlreadyOpen(Exception):
    """같은 트레이너를 처리 전에 이미 신고했다 — 409."""


class ReportNotFound(Exception):
    """처리할 신고가 없다 — 404."""


class ReportAlreadyClosed(Exception):
    """이미 처리한 신고다 — 409."""


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _has_open(db: Session, trainer_id: str, reporter_id: str) -> bool:
    return (
        db.scalar(
            select(TrainerReport.id).where(
                TrainerReport.trainer_id == trainer_id,
                TrainerReport.reporter_id == reporter_id,
                TrainerReport.status == OPEN,
            )
        )
        is not None
    )


def create_report(
    db: Session, *, reporter_id: str, trainer_id: str, payload: TrainerReportCreate
) -> TrainerReportOut:
    """회원이 트레이너를 신고한다."""
    trainer = db.get(User, trainer_id)
    if trainer is None or trainer.role != "trainer":
        raise TrainerNotFound("트레이너를 찾을 수 없어요.")
    if _has_open(db, trainer_id, reporter_id):
        raise ReportAlreadyOpen("이미 신고한 트레이너예요. 운영자가 확인하고 있어요.")

    row = TrainerReport(
        id=f"trp-{uuid.uuid4().hex[:12]}",
        trainer_id=trainer_id,
        reporter_id=reporter_id,
        reason=payload.reason,
        memo=payload.memo,
        status=OPEN,
    )
    db.add(row)
    try:
        db.commit()
    except IntegrityError as exc:
        # 같은 회원의 두 요청이 겹치면 부분 유니크가 한쪽을 막는다.
        db.rollback()
        raise ReportAlreadyOpen(
            "이미 신고한 트레이너예요. 운영자가 확인하고 있어요."
        ) from exc
    db.refresh(row)
    return TrainerReportOut(id=row.id, status=row.status, created_at=row.created_at)


def _admin_out(report: TrainerReport, trainer: User) -> AdminTrainerReportOut:
    return AdminTrainerReportOut(
        id=report.id,
        trainer_id=trainer.id,
        trainer_name=trainer.name or "",
        trainer_email=trainer.email or "",
        trainer_is_active=bool(trainer.is_active),
        reason=report.reason,
        memo=report.memo or "",
        status=report.status,
        created_at=report.created_at,
        resolved_at=report.resolved_at,
    )


def list_reports(db: Session, *, status: str = OPEN) -> list[AdminTrainerReportOut]:
    """운영 화면의 신고 목록. `open`(기본)·`closed`(처리됨)·`all`, 최근 순."""
    query = select(TrainerReport, User).join(User, User.id == TrainerReport.trainer_id)
    if status == OPEN:
        query = query.where(TrainerReport.status == OPEN)
    elif status == "closed":
        query = query.where(TrainerReport.status != OPEN)
    query = query.order_by(
        TrainerReport.created_at.desc(), TrainerReport.id
    ).limit(LIST_LIMIT)
    return [_admin_out(report, trainer) for report, trainer in db.execute(query)]


def close_report(
    db: Session, report_id: str, *, outcome: str, admin_id: str
) -> AdminTrainerReportOut:
    """신고를 처리한다 — `resolved`(조치함) 또는 `dismissed`(조치 없이 넘김)."""
    row = db.execute(
        select(TrainerReport, User)
        .join(User, User.id == TrainerReport.trainer_id)
        .where(TrainerReport.id == report_id)
    ).first()
    if row is None:
        raise ReportNotFound("신고를 찾을 수 없어요.")
    report, trainer = row
    if report.status != OPEN:
        raise ReportAlreadyClosed("이미 처리한 신고예요.")
    report.status = RESOLVED if outcome == RESOLVED else DISMISSED
    report.resolved_at = _now()
    report.resolved_by = admin_id
    db.commit()
    db.refresh(report)
    return _admin_out(report, trainer)


def open_counts(db: Session, trainer_ids: list[str]) -> dict[str, int]:
    """트레이너별 처리 전 신고 수."""
    if not trainer_ids:
        return {}
    rows = db.execute(
        select(TrainerReport.trainer_id, func.count())
        .where(
            TrainerReport.trainer_id.in_(trainer_ids),
            TrainerReport.status == OPEN,
        )
        .group_by(TrainerReport.trainer_id)
    ).all()
    return {trainer_id: int(count) for trainer_id, count in rows}
