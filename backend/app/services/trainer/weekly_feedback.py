"""트레이너 도메인 — 회원 주간 피드백. (#2232)"""
from __future__ import annotations

import uuid
from datetime import date, datetime, timezone

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.models import (
    MemberWeeklyFeedback,
)
from app.schemas.trainer_api import (
    MemberWeeklyFeedbackOut,
)


# ── 회원 주간 피드백 (#2232) ────────────────────────────────────────────────
#
# 회원이 한 주를 끝내며 남기는 세 문항. 회원 앱이 쓰고 트레이너 리포트가 읽는다 —
# 양쪽이 같은 함수를 지나야 주차 정규화가 한 곳에서만 일어난다.


#: 고를 수 있는 값. 모델의 `CheckConstraint` 와 같은 목록이라 한쪽만 늘리면
#: 저장이 DB 에서 막힌다 — 둘을 함께 고친다.
_WEEKLY_FEEDBACK_CONDITIONS = ("great", "good", "ok", "tired", "bad")


_WEEKLY_FEEDBACK_INTENSITIES = ("too_easy", "right", "hard", "too_hard")


def get_member_weekly_feedback(
    db: Session, member_id: str, week: date
) -> MemberWeeklyFeedbackOut:
    """그 주에 회원이 남긴 답. 없으면 `submitted=False` 로 답한다.

    404 를 쓰지 않는 이유는 `get_report_feedback` 과 같다 — 답이 없는 것은
    오류가 아니라 아직 안 낸 정상 상태다. 트레이너 화면은 그때 그 칸에
    "아직 받지 못함" 을 적어야 하는데, 오류로 만들면 칸이 통째로 사라진다.
    """
    row = _member_weekly_feedback_row(db, member_id, week)
    if row is None:
        return MemberWeeklyFeedbackOut(week_start=week.isoformat())
    return _member_weekly_feedback_out(row, week)


def save_member_weekly_feedback(
    db: Session,
    member_id: str,
    week: date,
    *,
    condition: str,
    intensity: str,
    pain_area: str = "",
    pain_on: str = "",
    note: str = "",
) -> MemberWeeklyFeedbackOut:
    """회원의 그 주 답을 저장한다. 같은 주에 다시 보내면 덮어쓴다.

    한 주에 대한 회원의 말은 마지막 것 하나다 — 고쳐 보낸 답이 먼저 보낸 답
    옆에 나란히 서면 트레이너는 둘 중 무엇을 믿을지 알 수 없다.

    통증은 있을 때만 적는다. 아픈 곳을 비운 채 날짜만 오면 날짜도 버린다 —
    가리키는 곳이 없는 날짜는 화면에서 읽을 수 없다.
    """
    if condition not in _WEEKLY_FEEDBACK_CONDITIONS:
        raise HTTPException(status_code=422, detail="invalid condition")
    if intensity not in _WEEKLY_FEEDBACK_INTENSITIES:
        raise HTTPException(status_code=422, detail="invalid intensity")
    area = pain_area.strip()
    on = pain_on.strip() if area else ""
    row = _member_weekly_feedback_row(db, member_id, week)
    now = datetime.now(timezone.utc)
    if row is None:
        row = MemberWeeklyFeedback(
            id=f"mwf-{uuid.uuid4().hex[:12]}",
            user_id=member_id,
            week_start=week.isoformat(),
            condition=condition,
            intensity=intensity,
            pain_area=area,
            pain_on=on,
            note=note.strip(),
            created_at=now,
            updated_at=now,
        )
        db.add(row)
    else:
        row.condition = condition
        row.intensity = intensity
        row.pain_area = area
        row.pain_on = on
        row.note = note.strip()
        row.updated_at = now
    db.commit()
    db.refresh(row)
    return _member_weekly_feedback_out(row, week)


def _member_weekly_feedback_out(
    row: MemberWeeklyFeedback, week: date
) -> MemberWeeklyFeedbackOut:
    return MemberWeeklyFeedbackOut(
        week_start=week.isoformat(),
        submitted=True,
        condition=row.condition,
        intensity=row.intensity,
        pain_area=row.pain_area,
        pain_on=row.pain_on,
        note=row.note,
        submitted_at=row.updated_at,
    )


def _member_weekly_feedback_row(
    db: Session, member_id: str, week: date
) -> MemberWeeklyFeedback | None:
    return db.scalar(
        select(MemberWeeklyFeedback).where(
            MemberWeeklyFeedback.user_id == member_id,
            MemberWeeklyFeedback.week_start == week.isoformat(),
        )
    )
