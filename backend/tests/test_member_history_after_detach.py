"""담당이 바뀌거나 끊긴 뒤에도 회원의 지난 기록이 남는다. (#3347) DB 필요.

회원 본인의 조회는 지금의 담당이 아니라 **회원** 기준으로 센다.

- `GET /me/coach/sessions` — 지난 담당과 마친 PT 가 그 담당의 이름과 함께 남는다.
- `GET /me/coach/weekly-report` — PT 횟수·요일 이행률·개인운동 수가 담당 변경
  전후로 같다.
- `GET /me/coach/routines?date=` — 지난 날짜는 그날 걸려 있던 목록이다.
- `DELETE /me/coach/routines/{id}/complete` — 지난 담당의 배정에 남긴 완료를
  되돌릴 수 있다.

트레이너가 보는 값(로스터 이행률·리포트)은 바뀌지 않는다 — 자기 담당 기간의
것만 본다.

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
    TrainerClient,
    TrainerRoutine,
    TrainerSchedule,
    User,
)
from app.services.exercise_activity import noon
from app.services.trainer import member_mirror as trainer_member_mirror_service
from app.services.trainer import reports as trainer_reports_service
from app.services.trainer import routines as trainer_routines_service
from app.services.trainer._common import (
    DELIVERY_ROUTINE_ONLY,
    member_routine_days,
    member_routine_ends,
    week_completion_by_member,
)

#: 이 파일의 '오늘' — 일요일. 그 주(월~일)가 전부 지났거나 오늘이다.
TODAY = date(2026, 10, 4)
MONDAY = TODAY - timedelta(days=TODAY.weekday())
#: 이전 담당과 끊긴 날 — 그 주 목요일.
DETACHED = MONDAY + timedelta(days=3)


def _d(offset: int) -> date:
    """그 주 월요일에서 [offset] 일 뒤."""
    return MONDAY + timedelta(days=offset)


@dataclass
class World:
    """회원 하나와 그 회원이 거쳐 온 두 트레이너."""

    member_id: str
    #: 이전 담당 — 목요일에 끊겼다.
    old_id: str
    #: 지금 담당 — 목요일부터다.
    new_id: str


def _h(user_id: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(user_id)}"}


def _user(user_id: str, role: str, name: str) -> User:
    return User(
        id=user_id,
        email=f"{user_id}@oncare.com",
        name=name,
        hashed_password="unused",
        role=role,
    )


@pytest.fixture()
def today(monkeypatch) -> date:
    moment = datetime(TODAY.year, TODAY.month, TODAY.day, 12, tzinfo=clock.SEOUL)
    monkeypatch.setattr(clock, "now", lambda: moment)
    assert clock.today() == TODAY
    return TODAY


def _link(
    db_session,
    trainer_id: str,
    member_id: str,
    *,
    active: bool,
    revoked_on: date | None = None,
) -> TrainerClient:
    link = TrainerClient(
        id=f"tc-{uuid4().hex[:12]}",
        trainer_id=trainer_id,
        member_id=member_id,
        active=active,
        data_consent_at=clock.now() if active else None,
        data_consent_revoked_at=noon(revoked_on) if revoked_on else None,
    )
    db_session.add(link)
    db_session.commit()
    return link


@pytest.fixture()
def world(db_session, today) -> Iterator[World]:
    """이전 담당과 목요일에 끊기고 같은 날 새 담당과 이어진 회원."""
    suffix = uuid4().hex[:10]
    w = World(
        member_id=f"hd-member-{suffix}",
        old_id=f"hd-old-{suffix}",
        new_id=f"hd-new-{suffix}",
    )
    db_session.add_all(
        [
            _user(w.member_id, "member", "이력 확인 회원"),
            _user(w.old_id, "trainer", "이전 코치"),
            _user(w.new_id, "trainer", "새 코치"),
        ]
    )
    db_session.flush()
    _link(db_session, w.old_id, w.member_id, active=False, revoked_on=DETACHED)
    _link(db_session, w.new_id, w.member_id, active=True)
    try:
        yield w
    finally:
        db_session.rollback()
        db_session.execute(
            text("DELETE FROM users WHERE id = ANY(:ids)"),
            {"ids": [w.member_id, w.old_id, w.new_id]},
        )
        db_session.commit()


@pytest.fixture()
def solo(db_session, today) -> Iterator[World]:
    """담당이 한 명뿐인 회원 — `new_id` 는 아직 연결되지 않은 트레이너다."""
    suffix = uuid4().hex[:10]
    w = World(
        member_id=f"hs-member-{suffix}",
        old_id=f"hs-old-{suffix}",
        new_id=f"hs-new-{suffix}",
    )
    db_session.add_all(
        [
            _user(w.member_id, "member", "이력 확인 회원"),
            _user(w.old_id, "trainer", "이전 코치"),
            _user(w.new_id, "trainer", "새 코치"),
        ]
    )
    db_session.flush()
    _link(db_session, w.old_id, w.member_id, active=True)
    try:
        yield w
    finally:
        db_session.rollback()
        db_session.execute(
            text("DELETE FROM users WHERE id = ANY(:ids)"),
            {"ids": [w.member_id, w.old_id, w.new_id]},
        )
        db_session.commit()


def _routine(
    db_session,
    trainer_id: str | None,
    member_id: str,
    name: str,
    *,
    active_from: date,
    ended_on: date | None = None,
) -> TrainerRoutine:
    row = TrainerRoutine(
        id=f"rt-{uuid4().hex[:12]}",
        trainer_id=trainer_id,
        member_id=member_id,
        name=name,
        minutes=20,
        type="유산소",
        source="trainer" if trainer_id else "ai",
        sort_order=1,
        status="approved",
        delivery_kind=DELIVERY_ROUTINE_ONLY if trainer_id else None,
        active_from=active_from.isoformat(),
        ended_on=ended_on.isoformat() if ended_on else None,
        created_at=noon(active_from),
    )
    db_session.add(row)
    db_session.commit()
    return row


def _done(db_session, routine: TrainerRoutine, day: date) -> ExerciseSession:
    monday = day - timedelta(days=day.weekday())
    session = ExerciseSession(
        id=f"ex-{uuid4().hex[:12]}",
        user_id=routine.member_id,
        week_start=monday.isoformat(),
        day_label="월화수목금토일"[day.weekday()],
        type="cardio",
        name=routine.name,
        minutes=20,
        calories=100,
        source="assigned_routine",
        assigned_routine_id=routine.id,
        assigned_trainer_id=routine.trainer_id,
        assigned_routine_name=routine.name,
        completed_at=noon(day),
        created_at=noon(day),
    )
    db_session.add(session)
    db_session.commit()
    return session


def _pt(
    db_session,
    trainer_id: str,
    member_id: str,
    day: date,
    status: str = "완료",
    *,
    type_: str = "1:1 PT",
    time: str = "10:00",
    note: str = "",
) -> TrainerSchedule:
    row = TrainerSchedule(
        id=f"sch-{uuid4().hex[:12]}",
        trainer_id=trainer_id,
        member_id=member_id,
        date=day.isoformat(),
        time=time,
        client_name="이력 확인 회원",
        type=type_,
        duration_minutes=50,
        status=status,
        note=note,
    )
    db_session.add(row)
    db_session.commit()
    return row


@dataclass
class Week:
    """[world] 에 얹는 한 주 — 월~수는 이전 담당, 목~일은 새 담당."""

    old_routine: TrainerRoutine
    new_routine: TrainerRoutine
    old_pt: TrainerSchedule
    new_pt: TrainerSchedule


def _week(db_session, w: World) -> Week:
    # 이전 담당의 배정은 끊긴 뒤에도 `ended_on` 이 찍히지 않는다.
    old_routine = _routine(
        db_session, w.old_id, w.member_id, "걷기", active_from=_d(-7)
    )
    new_routine = _routine(
        db_session, w.new_id, w.member_id, "스쿼트", active_from=DETACHED
    )
    _done(db_session, old_routine, _d(0))
    _done(db_session, old_routine, _d(1))
    _done(db_session, new_routine, _d(4))
    old_pt = _pt(db_session, w.old_id, w.member_id, _d(1), note="자세가 좋아졌어요")
    new_pt = _pt(db_session, w.new_id, w.member_id, _d(4))
    # 해제 때 거둔 이전 담당의 예정 일정.
    _pt(db_session, w.old_id, w.member_id, _d(5), "취소")
    return Week(old_routine, new_routine, old_pt, new_pt)


# ─────────────────────────────── PT 이력 ───────────────────────────────────


def _sessions(client, member_id: str) -> list[dict]:
    res = client.get("/v1/me/coach/sessions", headers=_h(member_id))
    assert res.status_code == 200, res.text
    return res.json()


def test_done_pt_with_the_previous_trainer_stays_in_the_list(
    client, db_session, world
):
    week = _week(db_session, world)

    by_id = {s["id"]: s for s in _sessions(client, world.member_id)}

    assert week.old_pt.id in by_id
    assert week.new_pt.id in by_id
    assert by_id[week.old_pt.id]["trainer_name"] == "이전 코치"
    assert by_id[week.new_pt.id]["trainer_name"] == "새 코치"
    # 완료 PT 의 피드백도 그대로 남는다.
    assert by_id[week.old_pt.id]["note"] == "자세가 좋아졌어요"


def test_session_number_counts_per_trainer(client, db_session, world):
    """회차는 그 담당과의 몇 번째 수업인가다 — 담당이 바뀌면 다시 1 부터다."""
    first_old = _pt(db_session, world.old_id, world.member_id, _d(0))
    second_old = _pt(db_session, world.old_id, world.member_id, _d(1))
    first_new = _pt(db_session, world.new_id, world.member_id, _d(4))

    numbers = {
        s["id"]: s["session_number"] for s in _sessions(client, world.member_id)
    }

    assert numbers[first_old.id] == 1
    assert numbers[second_old.id] == 2
    assert numbers[first_new.id] == 1


def test_only_done_pt_of_the_previous_trainer_is_listed(client, db_session, world):
    """끝난 관계의 취소·노쇼·예정·상담은 다시 띄우지 않는다."""
    hidden = [
        _pt(db_session, world.old_id, world.member_id, _d(0), "취소"),
        _pt(db_session, world.old_id, world.member_id, _d(1), "노쇼"),
        _pt(db_session, world.old_id, world.member_id, _d(2), "예정"),
        _pt(db_session, world.old_id, world.member_id, _d(2), type_="상담", time="15:00"),
    ]
    # 지금 담당의 것은 상태와 상관없이 전부 보인다.
    shown = [
        _pt(db_session, world.new_id, world.member_id, _d(4), "취소"),
        _pt(db_session, world.new_id, world.member_id, _d(5), "예정"),
    ]

    ids = {s["id"] for s in _sessions(client, world.member_id)}

    assert not ids & {row.id for row in hidden}
    assert {row.id for row in shown} <= ids


def test_history_stays_when_there_is_no_trainer_at_all(client, db_session, world):
    """담당 없음 상태에서도 마친 PT 는 회원의 이력이다 — 예전에는 빈 목록이었다."""
    week = _week(db_session, world)
    assert trainer_member_mirror_service.disconnect_member_coach(
        db_session, world.member_id
    )

    by_id = {s["id"]: s for s in _sessions(client, world.member_id)}

    assert {week.old_pt.id, week.new_pt.id} <= set(by_id)
    assert all(s["status"] == "완료" for s in by_id.values())
    assert by_id[week.new_pt.id]["trainer_name"] == "새 코치"


def test_cancellation_reason_of_detach_never_reaches_the_member(
    client, db_session, world
):
    """지난 담당의 행도 회원 응답의 가림 규칙(#3239)을 그대로 지난다."""
    week = _week(db_session, world)
    row = db_session.get(TrainerSchedule, week.old_pt.id)
    row.cancellation_reason = "내부 메모"
    db_session.commit()

    by_id = {s["id"]: s for s in _sessions(client, world.member_id)}

    assert by_id[week.old_pt.id]["cancellation_reason"] == ""
    assert by_id[week.old_pt.id]["consultation"] is None


def test_trainer_schedule_response_has_no_trainer_name(client, db_session, world):
    """`trainer_name` 은 회원 응답에만 싣는다 — 트레이너 응답은 그대로다."""
    week = _week(db_session, world)

    res = client.get(
        "/v1/trainer/schedule",
        params={"date": week.new_pt.date, "member_id": world.member_id},
        headers=_h(world.new_id),
    )

    assert res.status_code == 200, res.text
    mine = [s for s in res.json() if s["id"] == week.new_pt.id]
    assert mine and mine[0].get("trainer_name") is None


# ─────────────────────────────── 주간 리포트 ────────────────────────────────


def _my_report(client, member_id: str, monday: date = MONDAY) -> dict:
    res = client.get(
        "/v1/me/coach/weekly-report",
        params={"week_start": monday.isoformat()},
        headers=_h(member_id),
    )
    assert res.status_code == 200, res.text
    return res.json()


def test_member_week_counts_everything_hung_on_the_member(client, db_session, world):
    _week(db_session, world)

    body = _my_report(client, world.member_id)

    # 두 담당과 한 PT 가 다 든다. 취소된 일정은 세지 않는다(#871).
    assert body["sessions_booked"] == 2
    assert body["sessions_done"] == 2
    # 월: 걷기 완료 / 화: 걷기 완료 + PT / 수: 걷기 안 함 / 목: 스쿼트 안 함(걷기는
    # 담당이 끝난 날부터 없다) / 금: 스쿼트 완료 + PT / 토·일: 스쿼트 안 함.
    assert body["week_completion"] == [100, 100, 0, 0, 100, 0, 0]
    assert [d["assigned"] for d in body["days"]] == [1, 1, 1, 1, 1, 1, 1]
    assert [d["assigned_done"] for d in body["days"]] == [1, 1, 0, 0, 1, 0, 0]


def test_member_week_is_the_same_before_and_after_changing_trainer(
    client, db_session, solo
):
    """지난 주의 PT 횟수와 수행률이 담당 변경 전후로 같다."""
    last_monday = MONDAY - timedelta(days=7)
    routine = _routine(
        db_session, solo.old_id, solo.member_id, "걷기", active_from=last_monday
    )
    for offset in (0, 2, 3):
        _done(db_session, routine, last_monday + timedelta(days=offset))
    _pt(db_session, solo.old_id, solo.member_id, last_monday + timedelta(days=1))
    _pt(db_session, solo.old_id, solo.member_id, last_monday + timedelta(days=4), "예정")

    before = _my_report(client, solo.member_id, last_monday)
    assert before["sessions_booked"] == 2
    assert before["sessions_done"] == 1
    assert before["completion_avg"] is not None

    # 담당이 끊긴 것만으로도 같아야 한다.
    assert trainer_member_mirror_service.disconnect_member_coach(
        db_session, solo.member_id
    )
    detached = _my_report(client, solo.member_id, last_monday)
    # 새 담당과 이어진 뒤에도 같다.
    _link(db_session, solo.new_id, solo.member_id, active=True)
    _routine(db_session, solo.new_id, solo.member_id, "스쿼트", active_from=TODAY)
    changed = _my_report(client, solo.member_id, last_monday)

    for after in (detached, changed):
        assert after["sessions_booked"] == before["sessions_booked"]
        assert after["sessions_done"] == before["sessions_done"]
        assert after["week_completion"] == before["week_completion"]
        assert after["completion_avg"] == before["completion_avg"]
        assert after["days"] == before["days"]


def test_member_week_matches_the_trainer_while_there_is_one_trainer(
    client, db_session, solo
):
    """담당이 한 명뿐이던 주는 그 트레이너가 보는 값과 같다(#2652)."""
    routine = _routine(db_session, solo.old_id, solo.member_id, "걷기", active_from=MONDAY)
    _done(db_session, routine, _d(0))
    _pt(db_session, solo.old_id, solo.member_id, _d(2))

    mine = _my_report(client, solo.member_id)
    theirs = client.get(
        f"/v1/trainer/clients/{solo.member_id}/report",
        params={"week_start": MONDAY.isoformat()},
        headers=_h(solo.old_id),
    )
    assert theirs.status_code == 200, theirs.text

    their_body = theirs.json()
    mine.pop("message")
    their_body.pop("message")
    # 회원 응답에만 있는 칸 — 보낸 적 없는 주라 지금 값을 계산해 준 것이다(#3349).
    assert mine.pop("snapshot_at") is None
    assert mine == their_body


def test_previous_trainers_routine_does_not_hang_after_detach(db_session, world):
    """끊긴 담당의 배정은 `ended_on` 이 없어도 담당이 끝난 날부터 걸리지 않는다."""
    week = _week(db_session, world)

    days = member_routine_days(
        db_session, world.member_id, MONDAY, TODAY, member_scope=True
    )
    hung = {
        day.date: {item.routine_id for item in day.routines} for day in days
    }

    for offset in (0, 1, 2):
        assert hung[_d(offset)] == {week.old_routine.id}
    for offset in (3, 4, 5, 6):
        assert hung[_d(offset)] == {week.new_routine.id}


def test_completion_on_the_detach_day_still_counts(db_session, world):
    """담당이 끝난 날에 이미 한 것은 그날의 이행이다 — 빼면 한 일이 사라진다."""
    week = _week(db_session, world)
    _done(db_session, week.old_routine, DETACHED)

    completion = week_completion_by_member(
        db_session, "", [world.member_id], MONDAY, member_scope=True
    )[world.member_id]

    # 목: 걷기(이미 함) + 스쿼트(안 함) = 50.
    assert completion[3] == 50


def test_routine_ends_follow_the_link(db_session, world):
    week = _week(db_session, world)
    ended = _routine(
        db_session, world.old_id, world.member_id, "플랭크",
        active_from=_d(-7), ended_on=_d(1),
    )
    late = _routine(
        db_session, world.old_id, world.member_id, "런지", active_from=_d(5)
    )
    ai = _routine(
        db_session, None, world.member_id, "스트레칭",
        active_from=_d(0), ended_on=_d(1),
    )

    ends = member_routine_ends(
        db_session, [week.old_routine, week.new_routine, ended, late, ai]
    )

    # 끊긴 담당: 담당이 끝난 날. 그보다 먼저 내린 것은 내린 날 그대로.
    assert ends[week.old_routine.id] == DETACHED.isoformat()
    assert ends[ended.id] == _d(1).isoformat()
    # 걸리기도 전에 담당이 끝났으면 하루도 걸리지 않는다.
    assert ends[late.id] == late.active_from
    # 지금 담당과 AI 추천은 행의 값 그대로다.
    assert ends[week.new_routine.id] is None
    assert ends[ai.id] == _d(1).isoformat()


def test_routine_of_a_link_without_revoke_time_never_hangs(db_session, world):
    """끝난 날을 모르는 옛 링크의 배정은 끝없이 걸어 두지 않는다."""
    link = db_session.scalar(
        select(TrainerClient).where(
            TrainerClient.trainer_id == world.old_id,
            TrainerClient.member_id == world.member_id,
        )
    )
    link.data_consent_revoked_at = None
    db_session.commit()
    open_ended = _routine(
        db_session, world.old_id, world.member_id, "걷기", active_from=_d(-7)
    )
    closed = _routine(
        db_session, world.old_id, world.member_id, "플랭크",
        active_from=_d(-7), ended_on=_d(2),
    )

    ends = member_routine_ends(db_session, [open_ended, closed])

    assert ends[open_ended.id] == open_ended.active_from
    assert ends[closed.id] == _d(2).isoformat()


# ─────────────────────────── 트레이너가 보는 값은 그대로 ──────────────────────


def test_trainer_week_still_counts_only_their_own(db_session, world):
    _week(db_session, world)

    new_view = week_completion_by_member(
        db_session, world.new_id, [world.member_id], MONDAY
    )[world.member_id]
    report = trainer_reports_service.build_weekly_report(
        db_session, world.new_id, world.member_id, MONDAY
    )

    # 새 담당은 자기가 보낸 스쿼트와 자기 PT 만 본다 — 월~수는 걸린 것이 없다.
    assert new_view == [None, None, None, 0, 100, 0, 0]
    assert report.week_completion == new_view
    assert report.sessions_booked == 1
    assert report.sessions_done == 1
    assert [d.assigned for d in report.days] == [None, None, None, 1, 1, 1, 1]


def test_trainer_routine_days_ignore_other_trainers(db_session, world):
    week = _week(db_session, world)

    days = member_routine_days(
        db_session, world.member_id, MONDAY, TODAY, trainer_id=world.new_id
    )

    seen = {item.routine_id for day in days for item in day.routines}
    assert seen == {week.new_routine.id}


# ─────────────────────────── 지난 날짜 목록·완료 되돌리기 ─────────────────────


def _my_routines(client, member_id: str, day: date | None = None) -> list[dict]:
    res = client.get(
        "/v1/me/coach/routines",
        params={"date": day.isoformat()} if day else None,
        headers=_h(member_id),
    )
    assert res.status_code == 200, res.text
    return res.json()


def test_past_day_shows_what_hung_that_day(client, db_session, world):
    week = _week(db_session, world)

    tuesday = _my_routines(client, world.member_id, _d(1))
    friday = _my_routines(client, world.member_id, _d(4))
    today = _my_routines(client, world.member_id)

    # 화요일은 이전 담당의 목록이고 그날 완료가 그대로 보인다.
    assert [r["id"] for r in tuesday] == [week.old_routine.id]
    assert tuesday[0]["completed"] is True
    # 담당이 바뀐 뒤의 날에는 이전 담당의 것이 없다.
    assert [r["id"] for r in friday] == [week.new_routine.id]
    assert [r["id"] for r in today] == [week.new_routine.id]


def test_member_undoes_a_completion_of_the_previous_trainers_routine(
    client, db_session, world
):
    week = _week(db_session, world)

    res = client.delete(
        f"/v1/me/coach/routines/{week.old_routine.id}/complete",
        params={"date": _d(1).isoformat()},
        headers=_h(world.member_id),
    )

    assert res.status_code == 200, res.text
    assert res.json()["completed"] is False
    left = db_session.scalars(
        select(ExerciseSession.week_start, ExerciseSession.day_label).where(
            ExerciseSession.assigned_routine_id == week.old_routine.id
        )
    ).all()
    # 화요일 것만 지워지고 월요일 완료는 남는다.
    assert len(left) == 1
    assert _my_routines(client, world.member_id, _d(1))[0]["completed"] is False


def test_member_undoes_a_completion_with_no_trainer_at_all(client, db_session, world):
    week = _week(db_session, world)
    assert trainer_member_mirror_service.disconnect_member_coach(
        db_session, world.member_id
    )

    res = client.delete(
        f"/v1/me/coach/routines/{week.old_routine.id}/complete",
        params={"date": _d(0).isoformat()},
        headers=_h(world.member_id),
    )

    assert res.status_code == 200, res.text
    assert res.json()["completed"] is False


def test_member_cannot_undo_someone_elses_routine(client, db_session, world):
    """소유는 회원으로 본다 — 남의 배정은 여전히 404 다."""
    other = _user(f"hd-other-{uuid4().hex[:10]}", "member", "남의 회원")
    db_session.add(other)
    db_session.commit()
    try:
        theirs = _routine(db_session, world.old_id, other.id, "걷기", active_from=_d(0))
        _done(db_session, theirs, _d(0))

        res = client.delete(
            f"/v1/me/coach/routines/{theirs.id}/complete",
            params={"date": _d(0).isoformat()},
            headers=_h(world.member_id),
        )

        assert res.status_code == 404
        assert db_session.scalar(
            select(ExerciseSession.id).where(
                ExerciseSession.assigned_routine_id == theirs.id
            )
        ) is not None
    finally:
        db_session.rollback()
        db_session.execute(text("DELETE FROM users WHERE id = :id"), {"id": other.id})
        db_session.commit()


def test_member_completes_a_missed_past_day_of_the_previous_trainer(
    client, db_session, world
):
    """지난 날짜 목록에 뜨는 것은 나중에 체크할 수 있다(#2506) — 담당이 바뀌어도."""
    week = _week(db_session, world)

    res = client.post(
        f"/v1/me/coach/routines/{week.old_routine.id}/complete",
        params={"date": _d(2).isoformat()},
        json={"minutes": 20, "intensity": "moderate"},
        headers=_h(world.member_id),
    )

    assert res.status_code == 200, res.text
    row = db_session.scalar(
        select(ExerciseSession).where(
            ExerciseSession.assigned_routine_id == week.old_routine.id,
            ExerciseSession.day_label == "수",
        )
    )
    assert row is not None
    # 그 배정을 보낸 담당의 기록이다 — 지금 담당 것이 아니다.
    assert row.assigned_trainer_id == world.old_id


def test_previous_trainers_routine_cannot_be_completed_after_detach(
    client, db_session, world
):
    """담당이 끝난 뒤의 날과 오늘은 이전 담당의 배정을 완료할 수 없다."""
    week = _week(db_session, world)

    for params in ({"date": _d(4).isoformat()}, None):
        res = client.post(
            f"/v1/me/coach/routines/{week.old_routine.id}/complete",
            params=params,
            json={"minutes": 20, "intensity": "moderate"},
            headers=_h(world.member_id),
        )
        assert res.status_code == 404, res.text


def test_trainer_still_cannot_touch_another_trainers_routine(db_session, world):
    """배정을 고치는 경로는 여전히 보낸 트레이너만 된다."""
    week = _week(db_session, world)

    with pytest.raises(trainer_routines_service.RoutineNotFound):
        trainer_routines_service.delete_routine(
            db_session, world.new_id, world.member_id, week.old_routine.id
        )
