"""0102 마이그레이션 — 예약 일정의 '회원 앱 예약' 표식만 걷어 낸다. (#2575)"""
from __future__ import annotations

import importlib.util
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

from sqlalchemy import text

from app.models.models import (
    TrainerReservation,
    TrainerReservationSlot,
    TrainerSchedule,
)

_MIGRATION = (
    Path(__file__).resolve().parents[1]
    / "migrations"
    / "versions"
    / "0102_clear_reservation_note.py"
)


def _load_migration():
    spec = importlib.util.spec_from_file_location("m0102", _MIGRATION)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def _schedule(schedule_id: str, day: str) -> TrainerSchedule:
    return TrainerSchedule(
        id=schedule_id,
        trainer_id="trainer-demo",
        member_id="user-jisu",
        date=day,
        time="10:00",
        client_name="이지수",
        type="1:1 PT",
        duration_minutes=60,
        status="완료",
        note="회원 앱 예약",
        program_json="[]",
        sort_order=0,
    )


def test_upgrade_clears_marker_only_on_reserved_schedules(client, db_session):
    suffix = uuid4().hex[:8]
    day = (datetime.now(timezone.utc) - timedelta(days=3)).date().isoformat()
    slot = TrainerReservationSlot(
        id=f"slot-m0102-{suffix}",
        trainer_id="trainer-demo",
        starts_at=datetime.now(timezone.utc) - timedelta(days=3),
        capacity=1,
        remaining=0,
    )
    reserved = _schedule(f"sched-m0102-res-{suffix}", day)
    # 트레이너가 직접 같은 문구를 적은 일정 — 예약과 무관하니 그대로 둔다.
    typed = _schedule(f"sched-m0102-own-{suffix}", day)
    db_session.add_all([slot, reserved, typed])
    db_session.flush()
    db_session.add(
        TrainerReservation(
            id=f"res-m0102-{suffix}",
            member_id="user-jisu",
            slot_id=slot.id,
            schedule_id=reserved.id,
            status="booked",
        )
    )
    db_session.commit()

    migration = _load_migration()
    try:
        with patch.object(
            migration.op,
            "execute",
            side_effect=lambda sql: db_session.execute(text(sql)),
        ):
            migration.upgrade()
        db_session.commit()

        db_session.expire_all()
        assert db_session.get(TrainerSchedule, reserved.id).note == ""
        assert db_session.get(TrainerSchedule, typed.id).note == "회원 앱 예약"
    finally:
        db_session.rollback()
        db_session.query(TrainerReservation).filter(
            TrainerReservation.slot_id == slot.id
        ).delete(synchronize_session=False)
        db_session.query(TrainerSchedule).filter(
            TrainerSchedule.id.in_([reserved.id, typed.id])
        ).delete(synchronize_session=False)
        db_session.query(TrainerReservationSlot).filter(
            TrainerReservationSlot.id == slot.id
        ).delete(synchronize_session=False)
        db_session.commit()
