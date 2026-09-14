"""대시보드 `오늘 할 일` 진행 상태 — 계정 단위 저장. (#1633)

체크·삭제가 기기 로컬에만 있으면 센터 PC 에서 끝낸 항목이 태블릿에서는 다시 할
일로 남는다. 알림 수신 설정과 같은 이유로 계정에 둔다.

- **오늘은 서버가 정한다.** 쓸 수 있는 날짜는 KST 기준 오늘·어제뿐이다. 자정을
  넘겨 열어 둔 화면이 어제 칸을 마저 쓰는 것은 받고, 기기 시계가 크게 틀린 요청이
  엉뚱한 날에 기록되는 것은 422 로 막는다.
- **보관 기간은 [RETENTION_DAYS]일.** `할 일 진행률` 그래프는 이번 주와 8주 전까지
  되짚는다(월요일 기준 최대 62일 전). 쓸 때 그보다 오래된 행을 지운다.
"""
from __future__ import annotations

import json
from datetime import timedelta

from sqlalchemy import delete, func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import TrainerDailyTaskProgress
from app.schemas.trainer_api import (
    TrainerTaskProgressDayOut,
    TrainerTaskProgressOut,
    TrainerTaskProgressSave,
)

#: 이번 주 + 지난 8주(앱 `_maxTaskProgressWeeksBack`). 일요일에 8주 전 월요일까지
#: 되짚으면 오늘 포함 63일이다.
RETENTION_DAYS = 63


def oldest_kept_date() -> str:
    """보관하는 가장 이른 날 `YYYY-MM-DD`."""
    return (clock.today() - timedelta(days=RETENTION_DAYS - 1)).isoformat()


def writable_dates() -> tuple[str, str]:
    """저장을 받는 날짜 — KST 오늘과 어제."""
    today = clock.today()
    return today.isoformat(), (today - timedelta(days=1)).isoformat()


def _keys(raw: str) -> list[str]:
    try:
        decoded = json.loads(raw)
    except ValueError:
        return []
    return [k for k in decoded if isinstance(k, str)] if isinstance(decoded, list) else []


def _day_out(row: TrainerDailyTaskProgress) -> TrainerTaskProgressDayOut:
    return TrainerTaskProgressDayOut(
        date=row.date,
        total=row.total,
        completed_today=row.completed_today,
        completed_carried_over=row.completed_carried_over,
        pending_keys=_keys(row.pending_keys_json),
        dismissed_keys=_keys(row.dismissed_keys_json),
        completed_keys=(
            None if row.completed_keys_json is None else _keys(row.completed_keys_json)
        ),
    )


def build_progress(db: Session, trainer_id: str) -> TrainerTaskProgressOut:
    """`GET /trainer/dashboard/task-progress` 응답."""
    rows = db.scalars(
        select(TrainerDailyTaskProgress)
        .where(
            TrainerDailyTaskProgress.trainer_id == trainer_id,
            TrainerDailyTaskProgress.date >= oldest_kept_date(),
        )
        .order_by(TrainerDailyTaskProgress.date)
    ).all()
    return TrainerTaskProgressOut(
        first_saved_date=rows[0].date if rows else None,
        days=[_day_out(row) for row in rows],
    )


def save_day(
    db: Session, trainer_id: str, day: str, payload: TrainerTaskProgressSave
) -> TrainerTaskProgressDayOut:
    """그날의 진행 상태를 덮어쓴다. [day] 는 호출부가 [writable_dates] 로 확인한다.

    같은 날 요청이 두 기기에서 겹쳐도 기본키 충돌로 실패하지 않도록 upsert 한다 —
    나중에 도착한 쪽이 이긴다. 앱은 매번 그날 목록 전체를 보내므로 부분 병합할
    것이 없다.
    """
    values = {
        "total": payload.total,
        "completed_today": payload.completed_today,
        "completed_carried_over": payload.completed_carried_over,
        "pending_keys_json": json.dumps(sorted(set(payload.pending_keys))),
        "dismissed_keys_json": json.dumps(sorted(set(payload.dismissed_keys))),
        "completed_keys_json": (
            None
            if payload.completed_keys is None
            else json.dumps(sorted(set(payload.completed_keys)))
        ),
    }
    db.execute(
        insert(TrainerDailyTaskProgress)
        .values(trainer_id=trainer_id, date=day, **values)
        .on_conflict_do_update(
            index_elements=["trainer_id", "date"],
            set_={**values, "updated_at": func.now()},
        )
    )
    db.execute(
        delete(TrainerDailyTaskProgress).where(
            TrainerDailyTaskProgress.trainer_id == trainer_id,
            TrainerDailyTaskProgress.date < oldest_kept_date(),
        )
    )
    db.commit()
    row = db.get(TrainerDailyTaskProgress, (trainer_id, day))
    assert row is not None  # 방금 쓴 행이다.
    return _day_out(row)
