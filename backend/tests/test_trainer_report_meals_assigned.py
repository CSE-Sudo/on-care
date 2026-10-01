"""주간 리포트의 요일별 끼니 수·배정 개인운동 수. (#2772)

실서버 리포트 응답에 두 값이 없어 트레이너 웹 요일 표의 끼니 줄이 식단을 적은
날에도 `–` 였고, 자동 문구의 끼니 문장과 회원 PDF 의 끼니 칸이 빠졌다. 개인운동
칸은 분모가 "실제로 한 운동 수" 로 되돌아가 늘 꽉 찬 것처럼 보였다.

여기서 지키는 계약:

1. `meal_counts` 는 월→일 7칸, 그날 `DietEntry` 수다. 기록 없는 날은 0.
2. `days[].assigned` 는 그날 걸려 있던 **그 트레이너의** 추천 개인운동 수다
   (매일 리셋되는 목록, #2161). 배정이 없던 날·아직 오지 않은 날은 null —
   0 은 쉬는 날과 구분되지 않아 쓰지 않는다(#2232).

순수 함수는 DB 없이 돌고, 엔드포인트는 DB 필요(로컬 skip, CI 실행).
"""
from __future__ import annotations

import json
from datetime import date, timedelta
from types import SimpleNamespace
from uuid import uuid4

from app.core import clock
from tests.test_trainer_report import _auth, _trainer_token

MEMBER_ID = "user-jisu"


# ---- 순수 로직 ----


def _diet(day: str) -> SimpleNamespace:
    return SimpleNamespace(date=day)


def test_meal_counts_counts_entries_per_weekday():
    from app.services.trainer_service import _meal_counts

    monday = date(2026, 8, 3)
    rows = [
        _diet("2026-08-03"),
        _diet("2026-08-03"),
        _diet("2026-08-03"),
        _diet("2026-08-05"),
        _diet("2026-08-09"),
    ]

    assert _meal_counts(rows, monday) == [3, 0, 1, 0, 0, 0, 1]


def test_meal_counts_is_seven_zeros_without_records():
    from app.services.trainer_service import _meal_counts

    assert _meal_counts([], date(2026, 8, 3)) == [0] * 7


def test_meal_counts_ignores_entries_outside_the_week():
    """창은 칼로리·나트륨과 같다 — 앞뒤 주의 기록이 섞이지 않는다."""
    from app.services.trainer_service import _meal_counts

    rows = [_diet("2026-08-02"), _diet("2026-08-10"), _diet("2026-08-04")]

    assert _meal_counts(rows, date(2026, 8, 3)) == [0, 1, 0, 0, 0, 0, 0]


def test_week_days_carries_assigned_counts_per_weekday():
    from app.services.trainer_service import _week_days

    assigned = [2, None, 3, None, None, None, None]
    days = _week_days([], [0] * 7, assigned)

    assert [d.assigned for d in days] == assigned


def test_week_days_without_assigned_leaves_every_day_unknown():
    """배정을 모르면 null — 화면이 실제로 한 운동 수로 되돌아간다(#2232)."""
    from app.services.trainer_service import _week_days

    days = _week_days([], [0] * 7)

    assert [d.assigned for d in days] == [None] * 7


def test_weekly_report_out_accepts_old_shape_without_new_fields():
    """새 칸이 없는 옛 응답 모양도 그대로 세워진다 — 기본값은 빈 값이다."""
    from app.schemas.trainer_api import WeeklyReportDayOut, WeeklyReportOut

    report = WeeklyReportOut(
        member_id="m",
        member_name="김민수",
        week_start="2026-08-03",
        week_end="2026-08-09",
        sessions_booked=0,
        sessions_done=0,
        completion_avg=None,
        sodium_over_days=0,
        sodium_avg=None,
        message="",
    )

    assert report.meal_counts == []
    assert WeeklyReportDayOut(completion=0).assigned is None


# ---- 엔드포인트 ----


def _clear_last_week_diet(db_session, monday: date) -> None:
    from app.models.models import DietEntry

    db_session.query(DietEntry).filter(
        DietEntry.user_id == MEMBER_ID,
        DietEntry.date >= monday.isoformat(),
        DietEntry.date <= (monday + timedelta(days=6)).isoformat(),
    ).delete(synchronize_session=False)


def _meal(day: date, meal_type: str):
    from app.models.models import DietEntry

    return DietEntry(
        id=f"t-meal-{uuid4().hex[:8]}",
        user_id=MEMBER_ID,
        date=day.isoformat(),
        meal_type=meal_type,
        time_label="",
        foods_json=json.dumps([{"name": "테스트 끼니"}], ensure_ascii=False),
        total_calories=500,
        sodium_mg=600,
        sugar_g=5.0,
        engine="test",
    )


def _report(client, monday: date) -> dict:
    r = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/report",
        params={"week_start": monday.isoformat()},
        headers=_auth(_trainer_token(client)),
    )
    assert r.status_code == 200, r.text
    return r.json()


def test_report_carries_meal_counts_per_weekday(client, db_session):
    from app.services.trainer_service import week_start_of

    last_week = week_start_of(clock.today()) - timedelta(days=7)
    _clear_last_week_diet(db_session, last_week)
    tuesday = last_week + timedelta(days=1)
    thursday = last_week + timedelta(days=3)
    db_session.add_all(
        [
            _meal(tuesday, "breakfast"),
            _meal(tuesday, "lunch"),
            _meal(tuesday, "dinner"),
            _meal(thursday, "lunch"),
        ]
    )
    db_session.commit()

    body = _report(client, last_week)

    assert body["meal_counts"] == [0, 3, 0, 1, 0, 0, 0]


def test_report_meal_counts_are_zero_on_a_week_without_meals(client, db_session):
    """기록 없는 주도 7칸이다 — 화면이 요일 자리를 잃지 않는다."""
    from app.services.trainer_service import week_start_of

    last_week = week_start_of(clock.today()) - timedelta(days=7)
    _clear_last_week_diet(db_session, last_week)
    db_session.commit()

    assert _report(client, last_week)["meal_counts"] == [0] * 7


def test_report_counts_routines_active_on_each_day(client, db_session):
    """그날 걸려 있던 배정만 센다 — 기간 밖의 날은 늘지 않는다. (#2161)"""
    from app.models.models import TrainerRoutine
    from app.services.trainer_service import get_member_trainer_id, week_start_of

    last_week = week_start_of(clock.today()) - timedelta(days=7)
    trainer_id = get_member_trainer_id(db_session, MEMBER_ID)
    assert trainer_id is not None

    before = [d["assigned"] for d in _report(client, last_week)["days"]]

    # 화요일부터 목요일 전날(수요일)까지 걸려 있던 배정 둘.
    tuesday = last_week + timedelta(days=1)
    thursday = last_week + timedelta(days=3)
    ids = [f"t-rep-rt-{uuid4().hex[:8]}" for _ in range(2)]
    for routine_id in ids:
        db_session.add(
            TrainerRoutine(
                id=routine_id,
                trainer_id=trainer_id,
                member_id=MEMBER_ID,
                name="스쿼트",
                type="strength",
                status="approved",
                active_from=tuesday.isoformat(),
                ended_on=thursday.isoformat(),
            )
        )
    db_session.commit()
    try:
        after = [d["assigned"] for d in _report(client, last_week)["days"]]
    finally:
        for routine_id in ids:
            row = db_session.get(TrainerRoutine, routine_id)
            if row is not None:
                db_session.delete(row)
        db_session.commit()

    assert len(after) == 7
    for offset in (1, 2):
        assert after[offset] == (before[offset] or 0) + 2, offset
    for offset in (0, 3, 4, 5, 6):
        assert after[offset] == before[offset], offset


def test_report_ignores_another_trainers_routines(client, db_session):
    """다른 트레이너의 배정은 이 트레이너 리포트의 분모가 아니다."""
    from app.models.models import TrainerRoutine
    from app.services.trainer_service import week_start_of

    last_week = week_start_of(clock.today()) - timedelta(days=7)
    before = [d["assigned"] for d in _report(client, last_week)["days"]]

    routine_id = f"t-rep-other-{uuid4().hex[:8]}"
    db_session.add(
        TrainerRoutine(
            id=routine_id,
            trainer_id=None,
            member_id=MEMBER_ID,
            name="AI 추천 걷기",
            type="cardio",
            status="approved",
            active_from=last_week.isoformat(),
        )
    )
    db_session.commit()
    try:
        after = [d["assigned"] for d in _report(client, last_week)["days"]]
    finally:
        row = db_session.get(TrainerRoutine, routine_id)
        if row is not None:
            db_session.delete(row)
        db_session.commit()

    assert after == before


def test_report_leaves_days_not_yet_arrived_unknown(client, db_session):
    """아직 오지 않은 요일은 배정이 걸려 있어도 null 이다 — 0 을 쓰지 않는다."""
    from app.models.models import TrainerRoutine
    from app.services.trainer_service import get_member_trainer_id, week_start_of

    today = clock.today()
    this_week = week_start_of(today)
    trainer_id = get_member_trainer_id(db_session, MEMBER_ID)
    routine_id = f"t-rep-now-{uuid4().hex[:8]}"
    db_session.add(
        TrainerRoutine(
            id=routine_id,
            trainer_id=trainer_id,
            member_id=MEMBER_ID,
            name="플랭크",
            type="strength",
            status="approved",
            active_from=this_week.isoformat(),
        )
    )
    db_session.commit()
    try:
        days = _report(client, this_week)["days"]
    finally:
        row = db_session.get(TrainerRoutine, routine_id)
        if row is not None:
            db_session.delete(row)
        db_session.commit()

    assert len(days) == 7
    for offset in range(today.weekday() + 1):
        assert days[offset]["assigned"] is not None, offset
        assert days[offset]["assigned"] >= 1, offset
    for offset in range(today.weekday() + 1, 7):
        assert days[offset]["assigned"] is None, offset
    assert all(d["assigned"] != 0 for d in days)
