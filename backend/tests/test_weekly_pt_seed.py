"""데모 회원의 주간 PT 시드 — 리포트 PT 횟수가 0회로 서지 않게. (#2452)

예전 시드는 트레이너의 오늘 타임라인만 깔아서, 그 타임라인에 선 세 명을 뺀
회원은 리포트에서 매주 PT 0회였다. 실제 PT 회원은 매주 1회(몇 명은 2회) 수업을
받는다. 리포트의 PT 횟수는 스케줄 행을 그대로 세므로(`build_weekly_report`),
시드가 심은 행과 리포트 숫자가 같아야 한다.

DB 필요(로컬 skip, CI 의 Postgres 서비스에서 실행). client 픽스처가 init_db →
seed_member_health_data 를 먼저 돌린 상태를 검증한다.
"""
from __future__ import annotations

from datetime import date, timedelta

from sqlalchemy import func, select

from app.core import clock


def _monday(back: int = 0) -> date:
    today = clock.today()
    return today - timedelta(days=today.weekday()) - timedelta(weeks=back)


def _seed_rows(db_session, member_id: str, start: date, end: date):
    from app.db.seed_trainer import TRAINER_ID
    from app.models.models import TrainerSchedule

    return db_session.scalars(
        select(TrainerSchedule).where(
            TrainerSchedule.trainer_id == TRAINER_ID,
            TrainerSchedule.member_id == member_id,
            TrainerSchedule.date >= start.isoformat(),
            TrainerSchedule.date <= end.isoformat(),
            TrainerSchedule.id.like("seed-%"),
            TrainerSchedule.status != "공백",
        )
    ).all()


def _past_weeks():
    """이번 주를 뺀 이력 창의 주들(1주 전부터)."""
    from app.db.seed_member_data import _HISTORY_WEEKS

    return range(1, _HISTORY_WEEKS)


def test_weekly_pt_slots_stay_one_or_two_a_week():
    """자리표 자체가 주 1회(몇 명은 2회) 규칙을 지킨다."""
    from app.db.seed_member_data import _WEEKLY_PT
    from app.db.seed_trainer import _MEMBERS

    assert set(_WEEKLY_PT) == {user_id for user_id, *_ in _MEMBERS}
    counts = [len(slots) for slots in _WEEKLY_PT.values()]
    assert all(1 <= n <= 2 for n in counts)
    twice = sum(1 for n in counts if n == 2)
    assert 1 <= twice <= 5, "주 2회 회원은 몇 명뿐이어야 한다"


def test_weekly_pt_slots_never_overlap_the_timeline_or_each_other():
    """같은 요일의 수업끼리, 그리고 오늘 타임라인 칸과 겹치지 않는다."""
    from app.db.seed_member_data import _SCHEDULE, _WEEKLY_PT

    def minutes(hhmm: str) -> int:
        h, m = hhmm.split(":")
        return int(h) * 60 + int(m)

    timeline = [
        (mid, minutes(t), minutes(t) + dur)
        for t, _name, mid, _typ, dur, _status, _note, _program in _SCHEDULE
        if dur > 0
    ]
    for weekday in range(7):
        day = sorted(
            (minutes(at), minutes(at) + dur, member_id)
            for member_id, slots in _WEEKLY_PT.items()
            for wd, at, dur in slots
            if wd == weekday
        )
        for (_s1, e1, _m1), (s2, _e2, _m2) in zip(day, day[1:]):
            assert e1 <= s2, f"{weekday}요일 수업이 겹친다"
        for start, end, member_id in day:
            for owner, t_start, t_end in timeline:
                # 같은 회원의 타임라인 수업이 든 주는 주간 시드가 건너뛴다 —
                # 김민수의 18:00 은 오늘 PT 와 같은 그의 정해진 시각이다(#2567).
                if owner == member_id:
                    continue
                assert end <= t_start or t_end <= start, (
                    f"{weekday}요일 {start}분 수업이 타임라인과 겹친다"
                )
            # 저녁 칸은 트레이너가 직접 잡는 자리로 비워 둔다.
            assert end <= 19 * 60


def test_every_member_has_pt_in_each_past_week_since_joining(client, db_session):
    """붙은 뒤의 지난 주마다 1~2회, 붙기 전 주에는 0회."""
    from app.db.seed_member_data import _JOINED_WEEKS_AGO, _WEEKLY_PT, _valid_member_ids

    valid = _valid_member_ids(db_session)
    for member_id in _WEEKLY_PT:
        if member_id not in valid:
            continue
        joined = _JOINED_WEEKS_AGO.get(member_id)
        for back in _past_weeks():
            start = _monday(back)
            rows = _seed_rows(db_session, member_id, start, start + timedelta(days=6))
            if joined is not None and back > joined:
                assert rows == [], f"{member_id} 는 {joined}주 전에 붙었다 — {back}주 전"
                continue
            assert 1 <= len(rows) <= 2, f"{member_id} · {back}주 전 · {len(rows)}회"
            assert all(r.status == "완료" for r in rows)
            assert all(r.type == "1:1 PT" for r in rows)


def test_weekly_pt_never_seeds_today_or_later(client, db_session):
    """오늘과 남은 요일은 트레이너가 잡는 자리 — 시드가 미리 채우지 않는다."""
    from app.models.models import TrainerSchedule

    later = db_session.scalar(
        select(func.count())
        .select_from(TrainerSchedule)
        .where(
            TrainerSchedule.id.like("seed-pt-%"),
            TrainerSchedule.date >= clock.today_iso(),
        )
    )
    assert later == 0


def test_report_sessions_booked_matches_the_schedule(client, db_session):
    """리포트의 PT 횟수 == 그 주 스케줄의 예정·완료 수업 수(따로 센 값이 없다)."""
    from app.db.seed_member_data import _JOINED_WEEKS_AGO, _WEEKLY_PT, _valid_member_ids
    from app.db.seed_trainer import TRAINER_ID
    from app.models.models import TrainerSchedule
    from app.services.trainer_service import build_weekly_report

    valid = _valid_member_ids(db_session)
    for member_id in _WEEKLY_PT:
        if member_id not in valid:
            continue
        joined = _JOINED_WEEKS_AGO.get(member_id)
        for back in (1, 2, 5, max(_past_weeks())):
            start = _monday(back)
            report = build_weekly_report(db_session, TRAINER_ID, member_id, start)
            in_schedule = db_session.scalar(
                select(func.count())
                .select_from(TrainerSchedule)
                .where(
                    TrainerSchedule.trainer_id == TRAINER_ID,
                    TrainerSchedule.member_id == member_id,
                    TrainerSchedule.date >= start.isoformat(),
                    TrainerSchedule.date <= (start + timedelta(days=6)).isoformat(),
                    TrainerSchedule.status.in_(("예정", "완료")),
                )
            )
            assert report.sessions_booked == in_schedule, f"{member_id} · {back}주 전"
            if joined is None or back <= joined:
                assert report.sessions_booked >= 1, f"{member_id} · {back}주 전"


def test_weekly_pt_seed_is_idempotent(client, db_session):
    """다시 돌려도 행이 늘지 않는다."""
    from app.db.seed_member_data import _seed_weekly_pt, _valid_member_ids
    from app.models.models import TrainerSchedule

    def count() -> int:
        return db_session.scalar(
            select(func.count())
            .select_from(TrainerSchedule)
            .where(TrainerSchedule.id.like("seed-pt-%"))
        )

    before = count()
    assert before > 0
    valid = _valid_member_ids(db_session)
    _seed_weekly_pt(db_session, valid)
    _seed_weekly_pt(db_session, valid)
    db_session.expire_all()
    assert count() == before


def test_weekly_pt_seed_skips_a_week_that_already_has_a_session(client, db_session):
    """그 주에 다른 수업이 있으면 얹지 않는다 — 주 1회 회원이 2회로 부풀지 않게."""
    from app.db.seed_member_data import _SCHEDULE

    today_members = {mid for _t, _n, mid, typ, *_ in _SCHEDULE if mid and typ == "1:1 PT"}
    start = _monday(0)
    for member_id in today_members:
        seeded = [
            r
            for r in _seed_rows(db_session, member_id, start, start + timedelta(days=6))
            if r.id.startswith("seed-pt-")
        ]
        assert seeded == [], f"{member_id} 는 오늘 타임라인에 이미 수업이 있다"


def test_weekly_pt_seed_reattaches_rows_orphaned_by_account_recreation(client, db_session):
    """계정이 지워졌다 다시 생기면 FK 가 member_id 만 비운다 — 재시드가 주인을 되붙인다."""
    from app.db.seed_member_data import _seed_weekly_pt, _valid_member_ids
    from app.models.models import TrainerSchedule

    row = db_session.scalar(
        select(TrainerSchedule)
        .where(TrainerSchedule.id.like("seed-pt-%"))
        .order_by(TrainerSchedule.id)
        .limit(1)
    )
    assert row is not None
    row_id, owner = row.id, row.member_id
    row.member_id = None
    db_session.commit()
    try:
        _seed_weekly_pt(db_session, _valid_member_ids(db_session))
        db_session.expire_all()
        assert db_session.get(TrainerSchedule, row_id).member_id == owner
    finally:
        restored = db_session.get(TrainerSchedule, row_id)
        restored.member_id = owner
        db_session.commit()
