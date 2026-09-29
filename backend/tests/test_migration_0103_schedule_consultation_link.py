"""0103 마이그레이션 — 예전 수락이 만든 일정을 상담 요청에 잇고 종류·메모를 맞춘다. (#2584)"""
from __future__ import annotations

import importlib.util
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

from sqlalchemy import text

from app.models.models import ConsultationRequest, TrainerSchedule

_MIGRATION = (
    Path(__file__).resolve().parents[1]
    / "migrations"
    / "versions"
    / "0103_schedule_consultation_link.py"
)


def _load_migration():
    spec = importlib.util.spec_from_file_location("m0103", _MIGRATION)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def _request(request_id: str, day: str, time: str, status: str) -> ConsultationRequest:
    return ConsultationRequest(
        id=request_id,
        member_id="user-jisu",
        target_type="trainer",
        trainer_id="trainer-demo",
        exercise_goal="weight_loss",
        health_purpose_type="general",
        preferred_date=day,
        preferred_time_slot=time,
        message="무릎이 아파요",
        status=status,
        decided_by="trainer-demo",
    )


def _schedule(
    schedule_id: str, day: str, time: str, *, status: str, note: str
) -> TrainerSchedule:
    return TrainerSchedule(
        id=schedule_id,
        trainer_id="trainer-demo",
        member_id="user-jisu",
        date=day,
        time=time,
        client_name="이지수",
        type="1:1 PT",
        duration_minutes=30,
        status=status,
        note=note,
        program_json="[]",
        sort_order=0,
    )


def test_backfill_links_accepted_consultations_and_cleans_their_schedules(
    client, db_session
):
    suffix = uuid4().hex[:8]
    day = (datetime.now(timezone.utc) + timedelta(days=400)).date().isoformat()
    past = (datetime.now(timezone.utc) - timedelta(days=400)).date().isoformat()
    accepted = _request(f"consult-m0103-a-{suffix}", day, "07:10", "accepted")
    done_request = _request(f"consult-m0103-d-{suffix}", past, "07:10", "accepted")
    edited_request = _request(f"consult-m0103-e-{suffix}", day, "08:10", "accepted")
    rejected = _request(f"consult-m0103-r-{suffix}", day, "09:10", "rejected")
    # 예정 상담: 잇고, 종류를 상담으로, 문의 글이던 메모를 비운다.
    upcoming = _schedule(
        f"sched-m0103-up-{suffix}", day, "07:10", status="예정", note="무릎이 아파요"
    )
    # 완료된 PT: 이어도 종류는 두고(운동 기록이 파생돼 있다) 문의 글만 비운다.
    done = _schedule(
        f"sched-m0103-done-{suffix}", past, "07:10", status="완료", note="무릎이 아파요"
    )
    # 트레이너가 고쳐 쓴 메모는 남긴다.
    edited = _schedule(
        f"sched-m0103-ed-{suffix}", day, "08:10", status="예정", note="트레이너 메모"
    )
    # 거절된 요청과 같은 시각의 일정은 잇지 않는다.
    unrelated = _schedule(
        f"sched-m0103-un-{suffix}", day, "09:10", status="예정", note="무릎이 아파요"
    )
    requests = [accepted, done_request, edited_request, rejected]
    schedules = [upcoming, done, edited, unrelated]
    db_session.add_all(requests)
    db_session.flush()
    db_session.add_all(schedules)
    db_session.commit()

    migration = _load_migration()
    try:
        with patch.object(
            migration.op,
            "execute",
            side_effect=lambda sql: db_session.execute(text(sql)),
        ):
            migration.backfill()
        db_session.commit()

        db_session.expire_all()
        row = db_session.get(TrainerSchedule, upcoming.id)
        assert (row.consultation_id, row.type, row.note) == (accepted.id, "상담", "")
        row = db_session.get(TrainerSchedule, done.id)
        assert (row.consultation_id, row.type, row.note) == (
            done_request.id,
            "1:1 PT",
            "",
        )
        row = db_session.get(TrainerSchedule, edited.id)
        assert (row.consultation_id, row.type, row.note) == (
            edited_request.id,
            "상담",
            "트레이너 메모",
        )
        row = db_session.get(TrainerSchedule, unrelated.id)
        assert (row.consultation_id, row.type, row.note) == (
            None,
            "1:1 PT",
            "무릎이 아파요",
        )
    finally:
        db_session.rollback()
        db_session.query(TrainerSchedule).filter(
            TrainerSchedule.id.in_([s.id for s in schedules])
        ).delete(synchronize_session=False)
        db_session.query(ConsultationRequest).filter(
            ConsultationRequest.id.in_([r.id for r in requests])
        ).delete(synchronize_session=False)
        db_session.commit()
