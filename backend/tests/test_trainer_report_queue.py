"""리포트 작업대 요약 — `GET /trainer/reports/queue`, 칼로리 `평소`. (#2863, DB 필요)

작업대는 담당 회원 전원을 한 화면에 세운다. 예전에는 앱이 회원마다 주간
리포트와 회원 피드백을 따로 불러, 회원 N명이면 첫 화면에서만 요청 2N개가
나갔다. 이 엔드포인트는 큐가 쓰는 값(세션 예약·완료, 이행률)만 한 번에 준다.

편집기의 칼로리 `평소` 도 직전 4주 리포트를 다시 읽지 않고 리포트 응답의
`calorie_baseline` 으로 온다.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from uuid import uuid4

import pytest
from sqlalchemy import delete

from app.core.security import create_access_token
from app.models.models import (
    DietEntry,
    RoutineHistory,
    TrainerClient,
    TrainerSchedule,
    User,
)
from app.services.trainer import _common as trainer_common_service
from app.services.trainer import reports as trainer_reports_service

QUEUE = "/v1/trainer/reports/queue"

#: 지난 날짜로 고정한 한 주(월요일) — 오늘이 언제든 `아직 오지 않은 주` 가 아니다.
WEEK = date(2026, 2, 2)

_created: list[str] = []


@pytest.fixture(autouse=True)
def _drop_created_accounts(db_session):
    """이 파일이 만든 계정을 테스트마다 지운다 — 링크·일정·기록은 FK 로 함께 간다."""
    yield
    if not _created:
        return
    db_session.rollback()
    db_session.execute(delete(User).where(User.id.in_(list(_created))))
    db_session.commit()
    _created.clear()


def _h(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _user(db, prefix: str, role: str, name: str = "작업대 회원") -> str:
    user_id = f"{prefix}-{uuid4().hex[:10]}"
    _created.append(user_id)
    db.add(
        User(
            id=user_id,
            email=f"{user_id}@oncare.com",
            name=name,
            hashed_password="unused",
            role=role,
        )
    )
    db.commit()
    return user_id


def _trainer(db) -> str:
    return _user(db, "queue-trainer", "trainer", name="작업대 트레이너")


def _member(
    db,
    trainer_id: str,
    *,
    active: bool = True,
    revoked: bool = False,
    name: str = "작업대 회원",
) -> str:
    member_id = _user(db, "queue-member", "member", name=name)
    now = datetime.now(timezone.utc)
    db.add(
        TrainerClient(
            id=f"link-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            active=active,
            data_consent_at=None if revoked else now,
            data_consent_revoked_at=now if revoked else None,
        )
    )
    db.commit()
    return member_id


def _session(
    db, trainer_id: str, member_id: str, day: date, *, status: str, kind: str = "1:1 PT"
) -> None:
    db.add(
        TrainerSchedule(
            id=f"queue-s-{uuid4().hex[:10]}",
            trainer_id=trainer_id,
            member_id=member_id,
            date=day.isoformat(),
            time="10:00",
            client_name="작업대 회원",
            type=kind,
            duration_minutes=50,
            status=status,
        )
    )
    db.commit()


def _history(
    db, member_id: str, day: date, rate: int, *, trainer_id: str | None = None
) -> None:
    db.add(
        RoutineHistory(
            id=f"queue-h-{uuid4().hex[:10]}",
            member_id=member_id,
            trainer_id=trainer_id,
            date=day.isoformat(),
            kind_label="자율 운동",
            completion_rate=rate,
            exercises_json="[]",
        )
    )
    db.commit()


def _meal(db, member_id: str, day: date, kcal: int) -> None:
    db.add(
        DietEntry(
            id=f"queue-d-{uuid4().hex[:10]}",
            user_id=member_id,
            date=day.isoformat(),
            meal_type="lunch",
            time_label="",
            foods_json="[]",
            total_calories=kcal,
            engine="test",
        )
    )
    db.commit()


def _queue(client, trainer_id: str, week: date = WEEK) -> dict:
    r = client.get(
        QUEUE,
        params={"week_start": week.isoformat()},
        headers=_h(create_access_token(trainer_id)),
    )
    assert r.status_code == 200, r.text
    return r.json()


def _items(body: dict) -> dict[str, dict]:
    return {item["member_id"]: item for item in body["items"]}


def _day(offset: int) -> date:
    return WEEK + timedelta(days=offset)


# ---- 서비스 ----


def test_queue_matches_each_members_weekly_report(client, db_session):
    """큐의 수치는 회원별 리포트와 같은 규칙·같은 값이다 — 줄 순서·신호가 그대로다."""
    trainer = _trainer(db_session)
    busy = _member(db_session, trainer)
    quiet = _member(db_session, trainer)
    _session(db_session, trainer, busy, _day(0), status=trainer_common_service.SCHEDULE_DONE)
    _session(db_session, trainer, busy, _day(2), status=trainer_common_service.SCHEDULE_UPCOMING)
    _history(db_session, busy, _day(0), 90, trainer_id=trainer)
    _history(db_session, busy, _day(0), 60)  # 같은 날 여럿이면 최댓값
    _history(db_session, busy, _day(4), 40)

    queue = _items(
        trainer_reports_service.build_report_queue(db_session, trainer, WEEK).model_dump()
    )
    for member_id in (busy, quiet):
        report = trainer_reports_service.build_weekly_report(
            db_session, trainer, member_id, WEEK
        )
        item = queue[member_id]
        assert item["sessions_booked"] == report.sessions_booked
        assert item["sessions_done"] == report.sessions_done
        assert item["completion_avg"] == report.completion_avg
        assert item["week_completion"] == report.week_completion

    assert queue[busy]["sessions_booked"] == 2
    assert queue[busy]["sessions_done"] == 1
    assert queue[busy]["week_completion"] == [90, 0, 0, 0, 40, 0, 0]
    assert queue[busy]["completion_avg"] == 65
    # 기록이 없는 회원은 0% 가 아니라 null 이다.
    assert queue[quiet]["completion_avg"] is None
    assert queue[quiet]["week_completion"] == [0] * 7


def test_queue_skips_cancelled_no_show_and_consultation_sessions(client, db_session):
    """리포트처럼 취소·노쇼·상담은 예약 수에 넣지 않는다(#871, #2741)."""
    trainer = _trainer(db_session)
    member = _member(db_session, trainer)
    _session(db_session, trainer, member, _day(0), status=trainer_common_service.SCHEDULE_DONE)
    _session(db_session, trainer, member, _day(1), status=trainer_common_service.SCHEDULE_CANCELLED)
    _session(db_session, trainer, member, _day(2), status=trainer_common_service.SCHEDULE_NO_SHOW)
    _session(
        db_session,
        trainer,
        member,
        _day(3),
        status=trainer_common_service.SCHEDULE_UPCOMING,
        kind="상담",
    )
    item = _items(
        trainer_reports_service.build_report_queue(db_session, trainer, WEEK).model_dump()
    )[member]
    assert item["sessions_booked"] == 1
    assert item["sessions_done"] == 1


def test_queue_leaves_out_members_the_trainer_cannot_read(client, db_session):
    """담당 해제·동의 철회·남의 회원은 싣지 않는다 — 그 회원 리포트도 404 다."""
    trainer = _trainer(db_session)
    other = _trainer(db_session)
    mine = _member(db_session, trainer)
    ended = _member(db_session, trainer, active=False)
    revoked = _member(db_session, trainer, revoked=True)
    theirs = _member(db_session, other)
    _history(db_session, ended, _day(0), 80)
    _history(db_session, revoked, _day(0), 80)
    _history(db_session, theirs, _day(0), 80)

    ids = set(
        _items(
            trainer_reports_service.build_report_queue(db_session, trainer, WEEK).model_dump()
        )
    )
    assert ids == {mine}


def test_queue_does_not_count_another_trainers_guided_history(client, db_session):
    """다른 트레이너가 지도한 기록은 이 트레이너의 이행률에 들지 않는다(리포트와 같다)."""
    trainer = _trainer(db_session)
    other = _trainer(db_session)
    member = _member(db_session, trainer)
    _history(db_session, member, _day(1), 70, trainer_id=other)
    item = _items(
        trainer_reports_service.build_report_queue(db_session, trainer, WEEK).model_dump()
    )[member]
    assert item["completion_avg"] is None


def test_queue_is_empty_for_a_trainer_without_members(client, db_session):
    trainer = _trainer(db_session)
    out = trainer_reports_service.build_report_queue(db_session, trainer, WEEK)
    assert out.week_start == WEEK.isoformat()
    assert out.items == []


def test_queue_normalises_a_mid_week_day_to_monday(client, db_session):
    trainer = _trainer(db_session)
    member = _member(db_session, trainer)
    _history(db_session, member, _day(3), 50)
    out = trainer_reports_service.build_report_queue(db_session, trainer, _day(5))
    assert out.week_start == WEEK.isoformat()
    assert _items(out.model_dump())[member]["week_completion"][3] == 50


def test_queue_ignores_records_outside_the_week(client, db_session):
    trainer = _trainer(db_session)
    member = _member(db_session, trainer)
    _history(db_session, member, WEEK - timedelta(days=1), 90)
    _history(db_session, member, WEEK + timedelta(days=7), 90)
    _session(
        db_session,
        trainer,
        member,
        WEEK + timedelta(days=7),
        status=trainer_common_service.SCHEDULE_DONE,
    )
    item = _items(
        trainer_reports_service.build_report_queue(db_session, trainer, WEEK).model_dump()
    )[member]
    assert item["completion_avg"] is None
    assert item["sessions_booked"] == 0


# ---- 엔드포인트 ----


def test_endpoint_answers_every_readable_member_in_one_response(client, db_session):
    trainer = _trainer(db_session)
    members = [_member(db_session, trainer) for _ in range(3)]
    _history(db_session, members[0], _day(0), 100)
    body = _queue(client, trainer)
    assert body["week_start"] == WEEK.isoformat()
    items = _items(body)
    assert set(items) == set(members)
    assert items[members[0]]["completion_avg"] == 100


def test_endpoint_response_carries_exactly_what_the_app_reads(client, db_session):
    trainer = _trainer(db_session)
    member = _member(db_session, trainer)
    item = _items(_queue(client, trainer))[member]
    assert set(item) == {
        "member_id",
        "sessions_booked",
        "sessions_done",
        "completion_avg",
        "week_completion",
    }


def test_endpoint_defaults_to_this_week(client, db_session):
    trainer = _trainer(db_session)
    r = client.get(QUEUE, headers=_h(create_access_token(trainer)))
    assert r.status_code == 200, r.text
    assert r.json()["week_start"] == trainer_reports_service.week_start_of(
        date.fromisoformat(trainer_common_service.today_iso())
    ).isoformat()


def test_endpoint_rejects_a_malformed_week(client, db_session):
    trainer = _trainer(db_session)
    r = client.get(
        QUEUE,
        params={"week_start": "2026/02/02"},
        headers=_h(create_access_token(trainer)),
    )
    assert r.status_code == 422


def test_endpoint_rejects_a_future_week(client, db_session):
    trainer = _trainer(db_session)
    future = date.fromisoformat(trainer_common_service.today_iso()) + timedelta(days=14)
    r = client.get(
        QUEUE,
        params={"week_start": future.isoformat()},
        headers=_h(create_access_token(trainer)),
    )
    assert r.status_code == 422


def test_endpoint_requires_a_signed_in_trainer(client):
    assert client.get(QUEUE).status_code == 401


def test_endpoint_refuses_a_member_account(client, db_session):
    member = _user(db_session, "queue-only-member", "member")
    r = client.get(QUEUE, headers=_h(create_access_token(member)))
    assert r.status_code == 403


def test_endpoint_keeps_trainers_apart(client, db_session):
    trainer = _trainer(db_session)
    other = _trainer(db_session)
    mine = _member(db_session, trainer)
    theirs = _member(db_session, other)
    assert set(_items(_queue(client, trainer))) == {mine}
    assert set(_items(_queue(client, other))) == {theirs}


# ---- 칼로리 `평소` ----


def test_calorie_baseline_averages_recorded_days_of_the_four_weeks_before(
    client, db_session
):
    trainer = _trainer(db_session)
    member = _member(db_session, trainer)
    # 직전 4주 안 — 같은 날 두 끼는 합쳐 하루로 센다.
    _meal(db_session, member, WEEK - timedelta(days=1), 1500)
    _meal(db_session, member, WEEK - timedelta(days=1), 500)
    _meal(db_session, member, WEEK - timedelta(days=28), 1000)
    # 창 밖 — 5주 전과 이번 주는 세지 않는다.
    _meal(db_session, member, WEEK - timedelta(days=29), 9000)
    _meal(db_session, member, WEEK, 9000)

    report = trainer_reports_service.build_weekly_report(db_session, trainer, member, WEEK)
    assert report.calorie_baseline == pytest.approx(1500)


def test_calorie_baseline_is_null_without_records(client, db_session):
    trainer = _trainer(db_session)
    member = _member(db_session, trainer)
    _meal(db_session, member, WEEK, 2000)  # 이번 주 기록만 있다
    report = trainer_reports_service.build_weekly_report(db_session, trainer, member, WEEK)
    assert report.calorie_baseline is None


def test_calorie_baseline_skips_zero_calorie_days(client, db_session):
    """0kcal 로 적힌 날은 안 적은 날과 같다 — 평균을 끌어내리지 않는다."""
    trainer = _trainer(db_session)
    member = _member(db_session, trainer)
    _meal(db_session, member, WEEK - timedelta(days=3), 0)
    _meal(db_session, member, WEEK - timedelta(days=4), 1800)
    report = trainer_reports_service.build_weekly_report(db_session, trainer, member, WEEK)
    assert report.calorie_baseline == pytest.approx(1800)


def test_report_endpoint_carries_the_calorie_baseline(client, db_session):
    trainer = _trainer(db_session)
    member = _member(db_session, trainer)
    _meal(db_session, member, WEEK - timedelta(days=7), 2100)
    r = client.get(
        f"/v1/trainer/clients/{member}/report",
        params={"week_start": WEEK.isoformat()},
        headers=_h(create_access_token(trainer)),
    )
    assert r.status_code == 200, r.text
    assert r.json()["calorie_baseline"] == pytest.approx(2100)
