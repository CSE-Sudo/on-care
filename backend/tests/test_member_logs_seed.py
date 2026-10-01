"""담당 회원 데모 시드 — 주간 소모 목표·나이·지난 끼니·운동 세션·트레이너 기록.
(#2726, #2728, #2729, #2731)

DB 필요(로컬 skip, CI 의 Postgres 서비스에서 실행). client 픽스처가 init_db → 시드를
먼저 돌린 상태를 검증한다.
"""
from __future__ import annotations

import json
from datetime import date, timedelta
from types import SimpleNamespace

from sqlalchemy import select

from app.core import clock


# ---- #2726 주간 소모 칼로리 목표 ------------------------------------------------


def test_weekly_burn_goal_falls_back_to_daily_goal_times_seven():
    from app.services.exercise_service import weekly_goals

    def profile(**kw):
        base = {
            "weekly_exercise_minutes_goal": None,
            "weekly_burn_goal": None,
            "daily_burn_kcal": None,
        }
        base.update(kw)
        return SimpleNamespace(**base)

    # 저장된 주간 목표가 먼저다.
    assert weekly_goals(profile(weekly_burn_goal=1000, daily_burn_kcal=400)) == (150, 1000)
    # 없으면 회원의 하루 소모 목표 × 7 — 회원 앱·트레이너 웹과 같은 규칙.
    assert weekly_goals(profile(daily_burn_kcal=400)) == (150, 2800)
    # 둘 다 없으면 기본 하루 목표(300) × 7.
    assert weekly_goals(profile()) == (150, 2100)
    assert weekly_goals(None) == (150, 2100)


# ---- #2728 나이 -------------------------------------------------------------------


def test_age_on_counts_the_birthday():
    from app.services.profile_format import age_on

    assert age_on("1980-03-11", date(2026, 3, 10)) == 45
    assert age_on("1980-03-11", date(2026, 3, 11)) == 46
    assert age_on("", date(2026, 3, 11)) is None
    assert age_on("not-a-date", date(2026, 3, 11)) is None


def test_member_birth_dates_are_seeded(db_session):
    from app.db.seed_trainer import _MEMBER_BIRTH_DATES
    from app.models.models import HealthProfile

    for member_id, birth in _MEMBER_BIRTH_DATES.items():
        profile = db_session.scalar(
            select(HealthProfile).where(HealthProfile.user_id == member_id)
        )
        if profile is None:
            continue  # 계정 시드가 건너뛴 회원
        assert profile.birth_date, member_id
        # 회원이 고친 값은 덮지 않는다 — 시드값이거나 다른 유효한 날짜다.
        date.fromisoformat(profile.birth_date)
        if profile.birth_date == birth:
            break
    else:
        raise AssertionError("시드 생년월일이 하나도 들어가지 않았다")


def test_roster_carries_age_from_birth_date(client, db_session):
    from app.models.models import HealthProfile
    from app.services.profile_format import age_on

    token = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]
    roster = client.get(
        "/v1/trainer/clients", headers={"Authorization": f"Bearer {token}"}
    )
    assert roster.status_code == 200, roster.text
    by_id = {c["id"]: c for c in roster.json()}
    sera = by_id.get("user-sera")
    assert sera is not None
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == "user-sera")
    )
    assert sera["age"] == age_on(profile.birth_date, clock.today())
    assert sera["age"] is not None


# ---- #2729 지난 끼니·운동 세션 -------------------------------------------------------


def test_recent_days_are_split_into_meals_with_foods(db_session):
    from app.db.seed_member_logs import LOG_DAYS, MEAL_ID_PREFIX
    from app.models.models import DietEntry

    today = clock.today()
    since = (today - timedelta(days=LOG_DAYS - 1)).isoformat()
    rows = db_session.scalars(
        select(DietEntry).where(
            DietEntry.user_id == "user-woojin",
            DietEntry.date >= since,
            DietEntry.date <= today.isoformat(),
        )
    ).all()
    by_day: dict[str, list] = {}
    for r in rows:
        by_day.setdefault(r.date, []).append(r)
    split_days = [
        day for day, entries in by_day.items()
        if any(e.id.startswith(MEAL_ID_PREFIX) for e in entries)
    ]
    assert len(split_days) >= 14
    for day in split_days:
        entries = by_day[day]
        # 나눈 날에는 하루 한 줄 시드가 남지 않는다 — 합계가 두 번 잡히면 안 된다.
        assert not any(e.id.startswith("seed-roster-diet-") for e in entries), day
        for e in entries:
            foods = json.loads(e.foods_json)
            assert foods, day
            assert sum(f["calories"] for f in foods) == e.total_calories
            assert sum(f["sodium_mg"] for f in foods) == e.sodium_mg
            assert all(f["amount_g"] > 0 for f in foods)
            assert e.carbs_g + e.protein_g + e.fat_g > 0


def test_split_keeps_the_day_totals():
    from app.db.seed_member_logs import meals_for_day

    meals = meals_for_day(
        "user-sera", 8, date(2026, 9, 1),
        calories=1870, sodium_mg=2650, sugar_g=41.3,
    )
    assert len(meals) == 3  # 1,870kcal → 3끼(한 끼 600kcal)
    assert sum(m.total_calories for m in meals) == 1870
    assert sum(m.sodium_mg for m in meals) == 2650
    assert round(sum(m.sugar_g for m in meals), 1) == 41.3
    assert [m.meal_type for m in meals] == ["breakfast", "lunch", "dinner"]


def test_routine_sessions_are_seeded_by_type(db_session):
    from app.db.seed_member_logs import SESSION_ID_PREFIX
    from app.models.models import ExerciseSession

    sessions = db_session.scalars(
        select(ExerciseSession).where(
            ExerciseSession.user_id == "user-woojin",
            ExerciseSession.id.like(f"{SESSION_ID_PREFIX}%"),
        )
    ).all()
    assert sessions
    kinds = {s.type for s in sessions}
    assert "strength" in kinds
    for s in sessions:
        assert s.minutes > 0 and s.calories > 0
        if s.type == "strength":
            assert s.sets
        assert s.completed_at is not None


# ---- #2731 트레이너 기록 ------------------------------------------------------------


def test_trainer_notes_are_seeded(db_session):
    from app.db.seed_trainer import TRAINER_ID
    from app.models.models import (
        TrainerClientMemo,
        TrainerFollowUpTask,
        TrainerProgramDraft,
        TrainerSchedule,
    )

    follow_ups = db_session.scalars(
        select(TrainerFollowUpTask).where(
            TrainerFollowUpTask.id.like("seed-followup-%")
        )
    ).all()
    assert follow_ups
    today = clock.today().isoformat()
    assert any(
        t.status == "pending" and t.due_date < today for t in follow_ups
    ), "기한이 지난 할 일이 하나는 있어야 한다"
    assert any(t.status == "completed" for t in follow_ups)

    memos = db_session.scalars(
        select(TrainerClientMemo).where(TrainerClientMemo.id.like("seed-memo-note-%"))
    ).all()
    assert {m.source for m in memos} >= {"trainer", "exercise_memo"}

    drafts = db_session.scalars(
        select(TrainerProgramDraft).where(
            TrainerProgramDraft.trainer_id == TRAINER_ID,
            TrainerProgramDraft.id.like("seed-draft-%"),
        )
    ).all()
    assert len(drafts) == 3
    for d in drafts:
        sessions = json.loads(d.sessions_json)
        assert sessions and all(s["exercises"] for s in sessions)

    consults = db_session.scalars(
        select(TrainerSchedule).where(TrainerSchedule.id.like("seed-consult-%"))
    ).all()
    assert consults
    assert all(c.type == "상담" and c.note and c.member_id for c in consults)


def test_recent_pt_sessions_carry_notes(db_session):
    from app.db.seed_trainer import TRAINER_ID
    from app.models.models import TrainerSchedule

    today = clock.today()
    monday = today - timedelta(days=today.weekday())
    rows = db_session.scalars(
        select(TrainerSchedule).where(
            TrainerSchedule.trainer_id == TRAINER_ID,
            TrainerSchedule.id.like("seed-pt-%"),
            TrainerSchedule.date >= (monday - timedelta(weeks=2)).isoformat(),
            TrainerSchedule.date < monday.isoformat(),
        )
    ).all()
    assert any(r.note for r in rows)


def test_trainer_notes_seed_twice_adds_nothing(client, db_session):
    from app.db.seed_trainer_notes import seed_trainer_notes
    from app.models.models import TrainerFollowUpTask, TrainerSchedule

    def counts():
        return (
            len(db_session.scalars(select(TrainerFollowUpTask.id)).all()),
            len(db_session.scalars(
                select(TrainerSchedule.id).where(TrainerSchedule.id.like("seed-consult-%"))
            ).all()),
        )

    before = counts()
    seed_trainer_notes()
    db_session.expire_all()
    assert counts() == before
