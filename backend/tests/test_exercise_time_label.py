"""운동 기록의 시각 태그는 PT 수업 시각에만 있다. (#2692)

회원 앱은 `time_label` 을 "○○ 수업 완료" 로 그린다. 예전에는 유형별 기본 시각
(유산소 07:30 …)을 지어내, 지난 날짜의 `완료한 개인운동` 카드에 하지 않은 수업의
`07:30 수업 완료` 가 섰고, PT 카드도 실제 수업 시각이 아니라 유형 시각이었다.

앞의 둘은 DB 없이, 마지막 하나는 CI 의 Postgres 에서 돈다.
"""
from __future__ import annotations

from datetime import timedelta
from types import SimpleNamespace
from uuid import uuid4

from sqlalchemy import select

from app.core import clock
from app.services.exercise_service import (
    PT_EXERCISE_ID_PREFIX,
    WEEKDAY_LABELS,
    build_current_week,
)


def _row(row_id: str, source: str, type_: str = "cardio") -> SimpleNamespace:
    return SimpleNamespace(
        id=row_id,
        week_start="2026-09-14",
        day_label="수",
        type=type_,
        name="걷기",
        minutes=30,
        calories=100,
        source=source,
    )


def test_only_pt_carries_a_time_label():
    pt = _row(f"{PT_EXERCISE_ID_PREFIX}s-1", "trainer_pt", "strength")
    routine = _row("ex-routine", "assigned_routine")
    member = _row("ex-member", "member")

    sessions = build_current_week(
        [pt, routine, member], {pt.id: "19:00"}
    )["sessions"]

    labels = {s["source"]: s["time_label"] for s in sessions}
    assert labels == {
        "trainer_pt": "19:00",
        "assigned_routine": None,
        "member": None,
    }


def test_pt_without_a_known_class_has_no_time_label():
    # 수업을 찾지 못했으면 지어내지 않는다 — 근력이라고 18:00 을 붙이지 않는다.
    pt = _row(f"{PT_EXERCISE_ID_PREFIX}s-2", "trainer_pt", "strength")

    (session,) = build_current_week([pt])["sessions"]

    assert session["time_label"] is None


def _new_member(client) -> tuple[str, dict[str, str]]:
    email = f"tl-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register",
        json={"email": email, "password": "test-pw-1234", "name": "u"},
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    member_id = client.get("/v1/users/me", headers=headers).json()["id"]
    return member_id, headers


def test_week_reads_the_pt_time_from_its_class(client, db_session):
    from app.db.seed_trainer import TRAINER_ID
    from app.models.models import ExerciseSession, TrainerSchedule, User

    assert db_session.scalar(select(User.id).where(User.id == TRAINER_ID))
    member_id, headers = _new_member(client)
    today = clock.today()
    monday = today - timedelta(days=today.weekday())
    schedule_id = f"tl-{uuid4().hex[:8]}"
    # 수업은 id 로 이어진다 — 날짜는 오늘일 필요가 없다. 시드 트레이너의 오늘
    # 일정에 두면 같은 트레이너로 오늘 수업을 만드는 다른 시험이 겹침(409)으로
    # 떨어진다. 끝나면 만든 행을 지운다.
    db_session.add(
        TrainerSchedule(
            id=schedule_id,
            trainer_id=TRAINER_ID,
            member_id=member_id,
            date="2000-01-03",
            time="19:00",
            client_name="u",
            type="1:1 PT",
            duration_minutes=50,
            status="완료",
            note="",
            program_json="[]",
            sort_order=0,
        )
    )
    day_label = WEEKDAY_LABELS[today.weekday()]
    session_ids = (
        (f"{PT_EXERCISE_ID_PREFIX}{schedule_id}", "trainer_pt"),
        (f"tl-routine-{uuid4().hex[:6]}", "assigned_routine"),
    )
    for row_id, source in session_ids:
        db_session.add(
            ExerciseSession(
                id=row_id,
                user_id=member_id,
                week_start=monday.isoformat(),
                day_label=day_label,
                type="strength",
                name="레그프레스",
                minutes=30,
                calories=150,
                source=source,
            )
        )
    db_session.commit()

    try:
        r = client.get("/v1/exercise/weeks/current", headers=headers)
        assert r.status_code == 200, r.text

        labels = {s["source"]: s["time_label"] for s in r.json()["sessions"]}
        assert labels == {"trainer_pt": "19:00", "assigned_routine": None}
    finally:
        db_session.expire_all()
        for row_id, _source in session_ids:
            row = db_session.get(ExerciseSession, row_id)
            if row is not None:
                db_session.delete(row)
        schedule = db_session.get(TrainerSchedule, schedule_id)
        if schedule is not None:
            db_session.delete(schedule)
        db_session.commit()


def test_unlinked_pt_reads_the_same_day_class(client, db_session):
    """수업과 id 로 이어지지 않은 PT(픽스처 시드 기록)는 같은 날 완료 수업의 시각이다.
    (#2694)

    같은 날을 봐야 해서 오늘에 둔다. 시드 트레이너의 오늘 일정과 겹치지 않는 이른
    시각을 쓰고, 끝나면 만든 행을 지운다 — 남기면 오늘 수업을 만드는 다른 시험이
    겹침(409)으로 떨어진다.
    """
    from app.db.seed_trainer import TRAINER_ID
    from app.models.models import ExerciseSession, TrainerSchedule

    member_id, headers = _new_member(client)
    today = clock.today()
    monday = today - timedelta(days=today.weekday())
    schedule_id = f"tl-{uuid4().hex[:8]}"
    session_id = f"seed-fix-ex-{member_id}-{today.isoformat()}-0"
    db_session.add(
        TrainerSchedule(
            id=schedule_id,
            trainer_id=TRAINER_ID,
            member_id=member_id,
            date=today.isoformat(),
            time="05:00",
            client_name="u",
            type="1:1 PT",
            duration_minutes=50,
            status="완료",
            note="",
            program_json="[]",
            sort_order=0,
        )
    )
    db_session.add(
        ExerciseSession(
            id=session_id,
            user_id=member_id,
            week_start=monday.isoformat(),
            day_label=WEEKDAY_LABELS[today.weekday()],
            type="strength",
            name="벤치프레스",
            minutes=12,
            calories=72,
            source="trainer_pt",
        )
    )
    db_session.commit()

    try:
        r = client.get("/v1/exercise/weeks/current", headers=headers)
        assert r.status_code == 200, r.text
        (session,) = r.json()["sessions"]
        assert session["time_label"] == "05:00"
    finally:
        db_session.expire_all()
        for model, row_id in (
            (ExerciseSession, session_id),
            (TrainerSchedule, schedule_id),
        ):
            row = db_session.get(model, row_id)
            if row is not None:
                db_session.delete(row)
        db_session.commit()
