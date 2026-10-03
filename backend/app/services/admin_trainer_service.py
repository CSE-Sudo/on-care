"""운영 화면의 트레이너 검색·목록. (#3008)

신고 목록과 함께 트레이너 웹 `신고·계정 관리` 화면이 쓴다. 운영자는 이름·이메일로
트레이너를 찾아 계정을 정지하거나 해제한다(`account_suspension_service`).
"""
from __future__ import annotations

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.models.models import TrainerProfile, User
from app.schemas.admin_ops import AdminTrainerOut
from app.services import trainer_report_service

#: 한 번에 돌려주는 트레이너 수. 그 이상은 검색으로 좁힌다.
LIST_LIMIT = 100


def _escape_like(text: str) -> str:
    return text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def list_trainers(
    db: Session, *, q: str = "", state: str = "all"
) -> list[AdminTrainerOut]:
    """트레이너 목록. `q` 는 이름·이메일 부분 일치, `state` 는 all·active·suspended.

    처리 전 신고가 많은 트레이너가 먼저, 그다음 최근 가입 순이다.
    """
    query = (
        select(User, TrainerProfile)
        .outerjoin(TrainerProfile, TrainerProfile.trainer_id == User.id)
        .where(User.role == "trainer")
    )
    term = q.strip()
    if term:
        pattern = f"%{_escape_like(term.lower())}%"
        query = query.where(
            or_(
                func.lower(User.name).like(pattern, escape="\\"),
                func.lower(User.email).like(pattern, escape="\\"),
            )
        )
    if state == "active":
        query = query.where(User.is_active.is_(True))
    elif state == "suspended":
        query = query.where(User.is_active.is_(False))

    rows = db.execute(query).all()
    counts = trainer_report_service.open_counts(db, [user.id for user, _ in rows])
    out = [
        AdminTrainerOut(
            trainer_id=user.id,
            name=user.name or "",
            email=user.email or "",
            gym_name=(profile.gym_name if profile is not None else "") or "",
            gym_address=(profile.gym_address if profile is not None else "") or "",
            is_active=bool(user.is_active),
            created_at=user.created_at,
            open_reports=counts.get(user.id, 0),
        )
        for user, profile in rows
    ]
    epoch = 0.0
    out.sort(
        key=lambda t: (
            -t.open_reports,
            -(t.created_at.timestamp() if t.created_at else epoch),
            t.trainer_id,
        )
    )
    return out[:LIST_LIMIT]
