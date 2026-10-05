"""트레이너가 보는 날짜별 개인운동 이행과 그 쓰임새. DB 필요.

- #2508 `GET /trainer/clients/{id}/routine-days` — 날마다 그날 걸린 것과 결과
  (완료 / 다음 날 이후 체크 / 안 함 / 오늘 아직).
- #2510 운동 기록의 개인운동 완료는 하루 한 장 `개인운동` 카드로 묶인다.
- #2513 요일 이행률 = (완료한 개인운동 + 완료한 PT) ÷ (그날 걸린 개인운동 +
  잡힌 PT). 아무것도 걸리지 않은 날은 null.
- #2656 `개인운동만` 을 미래 시작일로 보내면 그날부터 한 주를 건다.

다른 테스트의 시드와 섞이지 않게 회원·트레이너를 새로 만들고, 서버의 '오늘' 을
고정한다.
"""
from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from uuid import uuid4

import pytest
from sqlalchemy import select, text

from app.core import clock
from app.core.security import create_access_token
from app.models.models import (
    ExerciseSession,
    Notification,
    TrainerClient,
    TrainerRoutine,
    TrainerSchedule,
    User,
)
from app.services import notification_templates
from app.services.exercise_activity import noon
from app.services.trainer import _common as trainer_common_service
from app.services.trainer import roster as trainer_roster_service
from app.services.trainer import routines as trainer_routines_service
from app.services.trainer import schedule as trainer_schedule_service
from app.services.trainer._common import DELIVERY_ROUTINE_ONLY
from app.services.trainer.schedule import PERSONAL_ROUTINE_ACTIVE_DAYS

#: 이 파일의 '오늘' — 목요일. 월~수가 지난 날이고 금~일이 아직 오지 않은 날이다.
TODAY = date(2026, 10, 1)
MONDAY = TODAY - timedelta(days=TODAY.weekday())


@dataclass
class Pair:
    trainer_id: str
    member_id: str


def _h(user_id: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(user_id)}"}


def _user(user_id: str, role: str) -> User:
    return User(
        id=user_id,
        email=f"{user_id}@oncare.com",
        name="개인운동 이행 확인",
        hashed_password="unused",
        role=role,
    )


@pytest.fixture()
def today(monkeypatch) -> date:
    moment = datetime(TODAY.year, TODAY.month, TODAY.day, 12, tzinfo=clock.SEOUL)
    monkeypatch.setattr(clock, "now", lambda: moment)
    assert clock.today() == TODAY
    return TODAY


@pytest.fixture()
def pair(db_session, today) -> Iterator[Pair]:
    suffix = uuid4().hex[:10]
    p = Pair(trainer_id=f"rd-trainer-{suffix}", member_id=f"rd-member-{suffix}")
    db_session.add_all([_user(p.trainer_id, "trainer"), _user(p.member_id, "member")])
    db_session.flush()
    db_session.add(
        TrainerClient(
            id=f"tc-{uuid4().hex[:12]}",
            trainer_id=p.trainer_id,
            member_id=p.member_id,
            active=True,
            data_consent_at=clock.now(),
        )
    )
    db_session.commit()
    try:
        yield p
    finally:
        db_session.rollback()
        db_session.execute(
            text("DELETE FROM users WHERE id = ANY(:ids)"),
            {"ids": [p.trainer_id, p.member_id]},
        )
        db_session.commit()


def _routine(
    db_session,
    p: Pair,
    name: str,
    *,
    active_from: date,
    ended_on: date | None,
    personal: bool = True,
    order: int = 1,
    sent: date | None = None,
) -> TrainerRoutine:
    row = TrainerRoutine(
        id=f"rt-{uuid4().hex[:12]}",
        trainer_id=p.trainer_id,
        member_id=p.member_id,
        name=name,
        minutes=20,
        type="유산소",
        source="trainer",
        sort_order=order,
        status="approved",
        delivery_kind=DELIVERY_ROUTINE_ONLY if personal else None,
        active_from=active_from.isoformat(),
        ended_on=ended_on.isoformat() if ended_on else None,
        created_at=noon(sent or active_from),
    )
    db_session.add(row)
    db_session.commit()
    return row


def _done(db_session, p: Pair, routine: TrainerRoutine, day: date, *, checked: date | None = None):
    monday = day - timedelta(days=day.weekday())
    session = ExerciseSession(
        id=f"ex-{uuid4().hex[:12]}",
        user_id=p.member_id,
        week_start=monday.isoformat(),
        day_label="월화수목금토일"[day.weekday()],
        type="cardio",
        name=routine.name,
        minutes=20,
        calories=100,
        source="assigned_routine",
        assigned_routine_id=routine.id,
        assigned_trainer_id=p.trainer_id,
        assigned_routine_name=routine.name,
        completed_at=noon(day),
        created_at=noon(checked or day),
    )
    db_session.add(session)
    db_session.commit()
    return session


def _pt(db_session, p: Pair, day: date, status: str, type_: str = "1:1 PT"):
    db_session.add(
        TrainerSchedule(
            id=f"sch-{uuid4().hex[:12]}",
            trainer_id=p.trainer_id,
            member_id=p.member_id,
            date=day.isoformat(),
            time="10:00",
            type=type_,
            duration_minutes=50,
            status=status,
        )
    )
    db_session.commit()


def _days(client, p: Pair, **params) -> dict:
    res = client.get(
        f"/v1/trainer/clients/{p.member_id}/routine-days",
        headers=_h(p.trainer_id),
        params=params,
    )
    assert res.status_code == 200, res.text
    return res.json()


def _status_by_day(body: dict, routine_id: str) -> dict[str, str]:
    return {
        day["date"]: item["status"]
        for day in body["days"]
        for item in day["items"]
        if item["routine_id"] == routine_id
    }


# ─────────────────────────────── #2508 날짜별 조회 ─────────────────────────


def test_each_day_says_done_late_missed_or_pending(client, db_session, pair):
    walk = _routine(
        db_session, pair, "걷기", active_from=MONDAY,
        ended_on=MONDAY + timedelta(days=PERSONAL_ROUTINE_ACTIVE_DAYS),
    )
    _done(db_session, pair, walk, MONDAY)
    # 화요일 것을 목요일(오늘)에 체크했다 — 완료이지만 몰아서 한 체크다.
    _done(db_session, pair, walk, MONDAY + timedelta(days=1), checked=TODAY)

    body = _days(client, pair, **{"from": MONDAY.isoformat()})

    assert body["start"] == MONDAY.isoformat()
    assert body["end"] == TODAY.isoformat()
    # 아직 오지 않은 날은 담지 않는다.
    assert [d["date"] for d in body["days"]] == [
        (MONDAY + timedelta(days=i)).isoformat() for i in range(4)
    ]
    assert _status_by_day(body, walk.id) == {
        MONDAY.isoformat(): "done",
        (MONDAY + timedelta(days=1)).isoformat(): "late",
        # 안 한 날은 오늘 이전만 `missed` 다.
        (MONDAY + timedelta(days=2)).isoformat(): "missed",
        TODAY.isoformat(): "pending",
    }
    done_item = body["days"][0]["items"][0]
    assert done_item["session_id"]
    assert body["days"][2]["items"][0]["session_id"] is None


def test_routines_carry_their_assignment_window(client, db_session, pair):
    personal = _routine(
        db_session, pair, "스쿼트", active_from=MONDAY,
        ended_on=MONDAY + timedelta(days=7),
    )
    standing = _routine(
        db_session, pair, "스트레칭", active_from=MONDAY - timedelta(days=20),
        ended_on=None, personal=False, order=2,
    )

    body = _days(client, pair, **{"from": MONDAY.isoformat()})
    by_id = {r["id"]: r for r in body["routines"]}

    assert by_id[personal.id]["personal"] is True
    assert by_id[personal.id]["active_from"] == MONDAY.isoformat()
    assert by_id[personal.id]["ended_on"] == (MONDAY + timedelta(days=7)).isoformat()
    assert by_id[personal.id]["sent_on"] == MONDAY.isoformat()
    # 줄을 `[유형] 이름 · 세부 · 효과` 로 그릴 값 — 효과는 비었으면 문구표다.
    assert by_id[personal.id]["minutes"] == 20
    assert by_id[personal.id]["effect"]
    # 기한 없는 따로 배정.
    assert by_id[standing.id]["personal"] is False
    assert by_id[standing.id]["ended_on"] is None


def test_from_defaults_to_the_first_assignment(client, db_session, pair):
    first = MONDAY - timedelta(days=9)
    _routine(db_session, pair, "걷기", active_from=first, ended_on=first + timedelta(days=7))

    body = _days(client, pair)

    assert body["start"] == first.isoformat()
    assert body["days"][0]["date"] == first.isoformat()


def test_no_assignment_gives_an_empty_answer(client, pair):
    body = _days(client, pair)
    assert body == {"start": None, "end": None, "routines": [], "days": []}


def test_an_old_routine_done_before_the_new_one_arrived_stays_on_that_day(
    client, db_session, pair
):
    swap = MONDAY + timedelta(days=2)
    old_done = _routine(db_session, pair, "옛 걷기", active_from=MONDAY - timedelta(days=4), ended_on=swap)
    old_skipped = _routine(
        db_session, pair, "옛 플랭크", active_from=MONDAY - timedelta(days=4), ended_on=swap, order=2
    )
    new = _routine(db_session, pair, "새 스쿼트", active_from=swap, ended_on=swap + timedelta(days=7), order=3)
    _done(db_session, pair, old_done, swap)

    body = _days(client, pair, **{"from": swap.isoformat(), "to": swap.isoformat()})
    statuses = {item["routine_id"]: item["status"] for item in body["days"][0]["items"]}

    # 그날 이미 한 옛 것은 남고, 하지 않은 옛 것은 그날 칸에 없다.
    assert statuses == {old_done.id: "done", new.id: "missed"}
    assert old_skipped.id not in statuses


def test_a_released_member_is_not_found(client, db_session, pair):
    db_session.execute(
        TrainerClient.__table__.update()
        .where(TrainerClient.member_id == pair.member_id)
        .values(active=False)
    )
    db_session.commit()

    res = client.get(
        f"/v1/trainer/clients/{pair.member_id}/routine-days",
        headers=_h(pair.trainer_id),
    )
    assert res.status_code == 404


# ─────────────────────────────── #2513 요일 이행률 ─────────────────────────


def test_week_completion_counts_personal_routines_and_pt(db_session, pair):
    a = _routine(db_session, pair, "걷기", active_from=MONDAY + timedelta(days=1), ended_on=MONDAY + timedelta(days=3))
    b = _routine(db_session, pair, "스쿼트", active_from=MONDAY + timedelta(days=1), ended_on=MONDAY + timedelta(days=3), order=2)
    # 월: PT 만 잡혀 있고 했다 → 100.
    _pt(db_session, pair, MONDAY, trainer_common_service.SCHEDULE_DONE)
    # 화: 개인운동 둘 중 하나 + PT 예정(안 함) → 1/3.
    _done(db_session, pair, a, MONDAY + timedelta(days=1))
    _pt(db_session, pair, MONDAY + timedelta(days=1), trainer_common_service.SCHEDULE_UPCOMING)
    # 수: 둘 다 했는데 하나는 다음 날 체크, 취소·노쇼·상담은 분모가 아니다 → 100.
    _done(db_session, pair, a, MONDAY + timedelta(days=2))
    _done(db_session, pair, b, MONDAY + timedelta(days=2), checked=TODAY)
    _pt(db_session, pair, MONDAY + timedelta(days=2), trainer_common_service.SCHEDULE_CANCELLED)
    _pt(db_session, pair, MONDAY + timedelta(days=2), trainer_common_service.SCHEDULE_NO_SHOW)
    _pt(db_session, pair, MONDAY + timedelta(days=2), trainer_common_service.SCHEDULE_UPCOMING, "상담")
    # 직접 추가한 운동은 세지 않는다 — 목요일에 걸린 것이 없으니 null 이다.
    db_session.add(
        ExerciseSession(
            id=f"ex-{uuid4().hex[:12]}",
            user_id=pair.member_id,
            week_start=MONDAY.isoformat(),
            day_label="목",
            type="cardio",
            name="혼자 달리기",
            minutes=30,
            calories=200,
            source="member",
            completed_at=noon(TODAY),
        )
    )
    db_session.commit()

    week = trainer_common_service.week_completion_by_member(
        db_session, pair.trainer_id, [pair.member_id], MONDAY
    )[pair.member_id]

    assert week == [100, 33, 100, None, None, None, None]


def test_report_and_roster_read_the_same_week(client, db_session, pair):
    walk = _routine(db_session, pair, "걷기", active_from=MONDAY, ended_on=MONDAY + timedelta(days=7))
    _done(db_session, pair, walk, MONDAY)

    report = client.get(
        f"/v1/trainer/clients/{pair.member_id}/report",
        headers=_h(pair.trainer_id),
        params={"week_start": MONDAY.isoformat()},
    )
    assert report.status_code == 200, report.text
    body = report.json()
    # 월 100, 화·수 0(걸렸는데 안 함), 목 0(오늘 아직), 금~일 null.
    assert body["week_completion"] == [100, 0, 0, 0, None, None, None]
    assert [d["completion"] for d in body["days"]] == body["week_completion"]
    # 0 인 날도 평균에 든다 — 걸렸는데 안 한 날이다.
    assert body["completion_avg"] == 25


# ─────────────────────────────── #2510 하루 한 장 ──────────────────────────


def test_history_groups_a_days_personal_routines_into_one_card(db_session, pair):
    tuesday = MONDAY + timedelta(days=1)
    walk = _routine(db_session, pair, "걷기", active_from=MONDAY, ended_on=MONDAY + timedelta(days=7))
    squat = _routine(db_session, pair, "스쿼트", active_from=MONDAY, ended_on=MONDAY + timedelta(days=7), order=2)
    plank = _routine(db_session, pair, "플랭크", active_from=MONDAY, ended_on=MONDAY + timedelta(days=7), order=3)
    walked = _done(db_session, pair, walk, tuesday)
    squatted = _done(db_session, pair, squat, tuesday)
    # 처방은 보통인데 회원이 높음으로 했다.
    squatted.intensity = "high"
    db_session.commit()
    today_walk = _done(db_session, pair, walk, TODAY)

    history = trainer_roster_service.build_client_history(db_session, pair.member_id, pair.trainer_id)
    personal = [h for h in history if h.kind == "personal_routine"]

    assert [h.date for h in personal] == [TODAY.isoformat(), tuesday.isoformat()]
    tue = personal[1]
    assert tue.id == f"personal-{tuesday.isoformat()}"
    assert tue.label == "개인운동"
    # 이름은 줄에만 — 배정 순서대로 ✓, ✓, ✗.
    assert [(i.name, i.done, i.session_id) for i in tue.exercise_items] == [
        ("걷기", True, walked.id),
        ("스쿼트", True, squatted.id),
        ("플랭크", False, None),
    ]
    assert tue.completion_rate == 67
    # 한 줄은 회원이 고른 강도와 처방 강도를 함께 싣는다 — 다르면 트레이너
    # 화면이 `수행 …` 을 붙인다. 안 한 줄은 처방 강도만(회색 태그).
    assert [
        (i.intensity, i.prescribed_intensity) for i in tue.exercise_items
    ] == [("moderate", "moderate"), ("high", "moderate"), ("moderate", None)]
    # 오늘 아직 안 한 것은 줄을 두지 않는다.
    assert [(i.name, i.session_id) for i in personal[0].exercise_items] == [
        ("걷기", today_walk.id)
    ]
    assert plank.id  # 지난 날 ✗ 줄의 출처


def test_history_skips_a_day_cut_by_the_read_limit(db_session, pair):
    """완료 기록을 [limit] 건만 읽어 일부만 읽힌 가장 오래된 날은 카드로 만들지
    않는다 — 만들면 한 운동이 ✗ 로 그려진다."""
    monday, tuesday = MONDAY, MONDAY + timedelta(days=1)
    walk = _routine(db_session, pair, "걷기", active_from=MONDAY, ended_on=MONDAY + timedelta(days=7))
    squat = _routine(db_session, pair, "스쿼트", active_from=MONDAY, ended_on=MONDAY + timedelta(days=7), order=2)
    for day in (monday, tuesday):
        _done(db_session, pair, walk, day)
        _done(db_session, pair, squat, day)

    # 4건 중 최근 3건만 읽는다 — 화요일 둘과 월요일 하나.
    history = trainer_roster_service.build_client_history(
        db_session, pair.member_id, pair.trainer_id, limit=3
    )
    personal = [h for h in history if h.kind == "personal_routine"]

    assert [h.date for h in personal] == [tuesday.isoformat()]
    assert all(i.done for i in personal[0].exercise_items)


# ─────────────────────────────── #2656 미래 시작일 ─────────────────────────


def _draft(name: str):
    from app.schemas.trainer_api import ProgramDraftExercise, ProgramDraftSession

    return ProgramDraftSession(
        id=uuid4().hex[:8],
        name=name,
        exercises=[ProgramDraftExercise(id=uuid4().hex[:8], name=name, type="유산소", duration=20)],
    )


def test_routine_only_with_a_future_start_runs_from_that_day(db_session, pair):
    start = TODAY + timedelta(days=4)
    current = _routine(db_session, pair, "지금 것", active_from=MONDAY, ended_on=MONDAY + timedelta(days=7))
    farther = _routine(
        db_session, pair, "더 먼 예약", active_from=start + timedelta(days=2),
        ended_on=start + timedelta(days=9), sent=TODAY,
    )

    created = trainer_routines_service.assign_program(
        db_session, pair.trainer_id, pair.member_id,
        name="이번 주 개인운동",
        sessions=[_draft("걷기"), _draft("자전거")],
        delivery_kind=DELIVERY_ROUTINE_ONLY,
        start_date=start,
        active_days=PERSONAL_ROUTINE_ACTIVE_DAYS,
        chat_card=False,
    )

    rows = db_session.scalars(
        select(TrainerRoutine).where(TrainerRoutine.id.in_([r.id for r in created]))
    ).all()
    for row in rows:
        assert row.active_from == start.isoformat()
        assert row.ended_on == (start + timedelta(days=7)).isoformat()
    db_session.refresh(current)
    db_session.refresh(farther)
    # 지금 것은 시작일 전날까지 걸려 있다가 시작일에 교대한다.
    assert current.ended_on == start.isoformat()
    # 시작일 뒤에야 걸리기로 했던 것은 걸리기 전에 내린다(제약 ended_on >= active_from).
    assert farther.ended_on == farther.active_from

    delivery = trainer_schedule_service.latest_delivery(db_session, pair.trainer_id, pair.member_id)
    assert delivery is not None
    # 보낸 날은 오늘이다 — 걸리는 첫날(미래)이 '보냄' 으로 찍히지 않는다.
    assert delivery.sent_on == TODAY
    assert {r.name for r in delivery.routines} == {"걷기", "자전거"}

    note = db_session.scalars(
        select(Notification)
        .where(Notification.user_id == pair.member_id)
        .order_by(Notification.created_at.desc())
    ).first()
    assert note is not None
    assert note.template_args["starts_on"] == start.isoformat()
    title, _ = notification_templates.render(note.template, note.template_args, "ko")
    assert title == f"{start.month}/{start.day}부터 할 개인운동이 왔어요"


def test_routine_only_for_today_still_runs_from_today(db_session, pair):
    created = trainer_routines_service.assign_program(
        db_session, pair.trainer_id, pair.member_id,
        name="이번 주 개인운동",
        sessions=[_draft("걷기")],
        delivery_kind=DELIVERY_ROUTINE_ONLY,
        start_date=TODAY,
        active_days=PERSONAL_ROUTINE_ACTIVE_DAYS,
        chat_card=False,
    )
    row = db_session.get(TrainerRoutine, created[0].id)
    assert row.active_from == TODAY.isoformat()
    assert row.ended_on == (TODAY + timedelta(days=7)).isoformat()
    note = db_session.scalars(
        select(Notification).where(Notification.user_id == pair.member_id)
    ).first()
    assert "starts_on" not in (note.template_args or {})


# ─────────────────────── #3106 회원 앱의 예정 한 줄 ────────────────────────


def _send(db_session, pair: Pair, start: date, *names: str):
    return trainer_routines_service.assign_program(
        db_session, pair.trainer_id, pair.member_id,
        name="이번 주 개인운동",
        sessions=[_draft(n) for n in names],
        delivery_kind=DELIVERY_ROUTINE_ONLY,
        start_date=start,
        active_days=PERSONAL_ROUTINE_ACTIVE_DAYS,
        chat_card=False,
    )


def test_member_sees_the_upcoming_routines_until_they_start(client, db_session, pair, monkeypatch):
    """미래 시작일로 받은 개인운동은 시작 전까지 예정으로, 시작일부터 그날 목록에 선다."""
    start = TODAY + timedelta(days=4)
    _send(db_session, pair, start, "걷기", "자전거")
    headers = _h(pair.member_id)

    upcoming = client.get("/v1/me/coach/routines/upcoming", headers=headers)
    assert upcoming.status_code == 200, upcoming.text
    assert upcoming.json() == {
        "starts_on": start.isoformat(),
        # 보낸 날은 오늘이다 — 걸리는 첫날이 아니다.
        "sent_on": TODAY.isoformat(),
        "names": ["걷기", "자전거"],
    }
    listed = client.get("/v1/me/coach/routines", headers=headers).json()
    assert not {r["name"] for r in listed} & {"걷기", "자전거"}

    # 시작일 — 그날 목록으로 넘어가고 예정에서 빠진다.
    moment = datetime(start.year, start.month, start.day, 12, tzinfo=clock.SEOUL)
    monkeypatch.setattr(clock, "now", lambda: moment)
    assert client.get("/v1/me/coach/routines/upcoming", headers=headers).json() is None
    listed = client.get("/v1/me/coach/routines", headers=headers).json()
    assert {"걷기", "자전거"} <= {r["name"] for r in listed}


def test_upcoming_is_the_latest_approved_send_only(db_session, pair):
    """다시 보내면 가장 최근 묶음 하나, 승인되지 않은 후보는 들지 않는다."""
    from app.services.trainer import member_mirror

    assert member_mirror.build_member_upcoming_routines(db_session, pair.member_id) is None

    candidate = _routine(
        db_session, pair, "검토 중 후보",
        active_from=TODAY + timedelta(days=2), ended_on=TODAY + timedelta(days=9), sent=TODAY,
    )
    candidate.status = "pending"
    db_session.commit()
    assert member_mirror.build_member_upcoming_routines(db_session, pair.member_id) is None

    _send(db_session, pair, TODAY + timedelta(days=4), "걷기")
    _send(db_session, pair, TODAY + timedelta(days=6), "런지", "플랭크")
    up = member_mirror.build_member_upcoming_routines(db_session, pair.member_id)
    assert up is not None
    assert up.starts_on == TODAY + timedelta(days=6)
    assert up.names == ["런지", "플랭크"]

    # 더 이른 시작일로 다시 보내면 늦은 묶음은 걸리기 전에 내려가고 새 것만 남는다.
    _send(db_session, pair, TODAY + timedelta(days=3), "스쿼트")
    up = member_mirror.build_member_upcoming_routines(db_session, pair.member_id)
    assert up is not None
    assert (up.starts_on, up.names) == (TODAY + timedelta(days=3), ["스쿼트"])

