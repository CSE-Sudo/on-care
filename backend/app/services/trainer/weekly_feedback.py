"""트레이너 도메인 — 회원 주간 피드백. (#2232)"""
from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import (
    MemberWeeklyFeedback,
    Notification,
    User,
)
from app.schemas.trainer_api import (
    MemberWeeklyFeedbackOut,
)
from app.services import notification_service, notification_templates


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
    trainer_id: str | None = None,
) -> MemberWeeklyFeedbackOut:
    """회원의 그 주 답을 저장한다. 같은 주에 다시 보내면 덮어쓴다.

    [trainer_id] 가 있으면 그 담당 트레이너에게 알린다(#3026) — 저장과 같은
    트랜잭션이라 함께 성사된다. 예전에는 저장만 해서 트레이너가 리포트 화면을 직접
    열어야 답이 왔는지 알았다.

    한 주에 대한 회원의 말은 마지막 것 하나다 — 고쳐 보낸 답이 먼저 보낸 답
    옆에 나란히 서면 트레이너는 둘 중 무엇을 믿을지 알 수 없다.

    통증은 있을 때만 적는다. 아픈 곳을 비운 채 날짜만 오면 날짜도 버린다 —
    가리키는 곳이 없는 날짜는 화면에서 읽을 수 없다. 남는 날짜는 **그 주 안**
    이어야 한다(#3368) — 앱은 그 주 7일만 고르게 하지만 서버가 형식만 보면 옛 앱이나
    직접 호출이 보낸 다른 주의 날짜가 그 주 리포트에 그대로 적힌다.

    첫 저장이 겹치면 한쪽은 유니크(`uq_member_weekly_feedback_user_week`)에 걸린다.
    그때는 먼저 들어간 행을 다시 읽어 덮어쓴다(#3368) — 같은 주에 다시 보낸 것과
    결과가 같아야 하고, 500 으로 끝나면 회원은 저장이 됐는지 알 수 없다.
    """
    if condition not in _WEEKLY_FEEDBACK_CONDITIONS:
        raise HTTPException(status_code=422, detail="invalid condition")
    if intensity not in _WEEKLY_FEEDBACK_INTENSITIES:
        raise HTTPException(status_code=422, detail="invalid intensity")
    area = pain_area.strip()
    on = pain_on.strip() if area else ""
    if on:
        _ensure_pain_day_in_week(on, week)
    row = _member_weekly_feedback_row(db, member_id, week)
    now = clock.now_utc()
    fresh: MemberWeeklyFeedback | None = None
    if row is None:
        fresh = MemberWeeklyFeedback(
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
        try:
            # savepoint 안에서 바로 내보낸다 — 충돌을 커밋 때가 아니라 여기서 알아야
            # 바깥 트랜잭션(알림 포함)을 살린 채 갱신으로 돌아설 수 있다.
            with db.begin_nested():
                db.add(fresh)
                db.flush()
            row = fresh
        except IntegrityError:
            row = _member_weekly_feedback_row(db, member_id, week)
            if row is None:
                # 유니크가 아닌 다른 제약에 걸린 것이다 — 삼키지 않는다.
                raise
    # 충돌로 돌아선 쪽도 고쳐 낸 답이다 — 먼저 들어간 답 위에 덮어쓴다.
    resubmitted = row is not fresh
    if resubmitted:
        row.condition = condition
        row.intensity = intensity
        row.pain_area = area
        row.pain_on = on
        row.note = note.strip()
        row.updated_at = now
    if trainer_id is not None:
        _notify_trainer(
            db,
            trainer_id=trainer_id,
            member_id=member_id,
            week=week,
            row=row,
            resubmitted=resubmitted,
            now=now,
        )
    db.commit()
    db.refresh(row)
    return _member_weekly_feedback_out(row, week)


def _ensure_pain_day_in_week(pain_on: str, week: date) -> None:
    """통증 날짜가 [week](월요일)부터 일요일까지 안에 있어야 한다 — 아니면 422.

    형식은 스키마가 먼저 본다(#3243). 여기서 다시 읽는 것은 범위를 재려면 날짜가
    필요해서이고, 스키마를 거치지 않은 호출도 같은 422 로 끝나게 하려는 것이다.
    """
    try:
        day = date.fromisoformat(pain_on)
    except ValueError as exc:
        raise HTTPException(
            status_code=422, detail="pain_on 은 YYYY-MM-DD 여야 해요."
        ) from exc
    if not week <= day <= week + timedelta(days=6):
        raise HTTPException(
            status_code=422, detail="pain_on 은 그 주 안의 날짜여야 해요."
        )


def _notify_trainer(
    db: Session,
    *,
    trainer_id: str,
    member_id: str,
    week: date,
    row: MemberWeeklyFeedback,
    resubmitted: bool,
    now: datetime,
) -> Notification | None:
    """담당 트레이너에게 주간 피드백 도착을 알린다. **커밋하지 않는다.** (#3026)

    같은 주에 고쳐 내면:

    - 트레이너가 아직 읽지 않은 그 주 알림이 있으면 **새로 만들지 않고** 그 행을
      최신 답으로 고쳐 쓰고 맨 위로 올린다. 답을 고칠 때마다 같은 회원 줄이
      알림함에 쌓이면 무엇이 최신인지 읽을 수 없다.
    - 이미 읽었으면 "피드백을 수정했어요" 로 한 건 더 만든다 — 트레이너가 본 답과
      달라졌다는 것을 알려야 한다.

    담당 회원 소식 알림을 껐으면 고쳐 쓰지도 않는다(#2420) — 이미 받은 줄이 끈 뒤에
    다시 맨 위로 올라오면 새 알림이 온 것과 같다.
    """
    if not notification_service.trainer_wants(
        db, trainer_id, notification_service.TRAINER_WEEKLY_FEEDBACK_KIND
    ):
        return None
    member_name = db.scalar(select(User.name).where(User.id == member_id)) or ""
    week_iso = week.isoformat()
    args = {
        "member_name": member_name.strip(),
        "condition": row.condition,
        "intensity": row.intensity,
        "pain": bool(row.pain_area),
    }
    unread = db.scalar(
        select(Notification)
        .where(
            Notification.user_id == trainer_id,
            Notification.category == notification_service.TRAINER_WEEKLY_FEEDBACK_KIND,
            Notification.subject_id == member_id,
            Notification.target_date == week_iso,
            Notification.read.is_(False),
        )
        .order_by(Notification.created_at.desc(), Notification.id.desc())
        .limit(1)
    )
    if unread is not None:
        # 읽지 않은 첫 알림을 고쳐 쓰는 것이라 '수정' 여부는 그 알림의 것을 따른다 —
        # 트레이너는 아직 먼저 낸 답을 보지 않았다.
        previous = unread.template_args or {}
        args["revised"] = bool(previous.get("revised"))
        cols = notification_service.texts(
            title=None,
            template=notification_templates.TRAINER_MEMBER_WEEKLY_FEEDBACK,
            template_args=args,
        )
        for key, value in cols.items():
            setattr(unread, key, value)
        unread.created_at = now
        return unread
    args["revised"] = resubmitted
    return notification_service.queue_for_trainer(
        db,
        trainer_id=trainer_id,
        kind=notification_service.TRAINER_WEEKLY_FEEDBACK_KIND,
        template=notification_templates.TRAINER_MEMBER_WEEKLY_FEEDBACK,
        template_args=args,
        subject_id=member_id,
        target_date=week_iso,
    )


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
