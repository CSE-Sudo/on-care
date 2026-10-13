"""주간 운동 챌린지 — 참가 기간·한 주 한 번·건 포인트·진행 세기·주 마감 판정. (#1789)
판정 앞의 하루 유예와 기록 마감, 미읽음 수 조회의 결과 알림 생성. (#3362)
DB 필요(로컬 skip, CI 실행).

요일은 `clock.now` 를 고정해 정한다. 토큰 발급·만료는 실제 시각을 쓰므로 고정해도
인증은 그대로다. 운동 기록은 적립(+20P)이 잔액 확인에 섞이지 않게 표에 직접 넣고,
앱 경로(`POST /exercise/sessions`)로 넣은 기록이 세지는지는 따로 확인한다.
"""
from __future__ import annotations

from datetime import date, datetime, time, timedelta
from uuid import uuid4

import pytest
from sqlalchemy import func, select

from app.core import clock
from app.models.models import (
    ExerciseSession,
    HealthProfile,
    Notification,
    PointsLedger,
    WeeklyChallenge,
)
from app.services import exercise_activity
from tests.exercise_helpers import post_exercise

#: 기준 주 — 2026-09-14(월) ~ 2026-09-20(일).
MON = date(2026, 9, 14)
TUE = MON + timedelta(days=1)
WED = MON + timedelta(days=2)
THU = MON + timedelta(days=3)
SAT = MON + timedelta(days=5)
SUN = MON + timedelta(days=6)
NEXT_MON = MON + timedelta(days=7)
#: 지난주 유예(월요일)가 끝나 판정하는 첫날.
NEXT_TUE = MON + timedelta(days=8)
NEXT_WED = MON + timedelta(days=9)

_LABELS = ("월", "화", "수", "목", "금", "토", "일")
_RESULT_TITLE = "주간 챌린지%"


@pytest.fixture
def at(monkeypatch):
    """`at(day, hour, minute)` 로 서비스 시각(KST)을 옮긴다."""

    def _set(day: date, hour: int = 10, minute: int = 0) -> None:
        moment = datetime.combine(day, time(hour, minute), tzinfo=clock.SEOUL)
        monkeypatch.setattr(clock, "now", lambda: moment)

    return _set


def _new_member(
    client, db_session, *, points: int = 1000, goal: int | None = None
) -> tuple[str, dict[str, str]]:
    email = f"chl-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    member_id = client.get("/v1/users/me", headers=headers).json()["id"]
    db_session.expire_all()
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    if profile is None:
        profile = HealthProfile(user_id=member_id)
        db_session.add(profile)
    profile.activity_points = points
    profile.weekly_workout_goal = goal
    db_session.commit()
    return member_id, headers


def _record(
    db_session,
    member_id: str,
    day: date,
    *,
    source: str = "member",
    stored_on: date | None = None,
) -> None:
    """[day] 의 운동 기록 한 건을 표에 직접 넣는다(적립 없이).

    저장 시각은 [stored_on](기본 그날) 정오(KST)다 — 판정이 기록 마감을 저장 시각으로
    본다(#3362).
    """
    monday = day - timedelta(days=day.weekday())
    db_session.add(
        ExerciseSession(
            id=f"ex-{uuid4().hex[:12]}",
            user_id=member_id,
            week_start=monday.isoformat(),
            day_label=_LABELS[day.weekday()],
            type="cardio",
            minutes=30,
            calories=120,
            source=source,
            completed_at=exercise_activity.noon(day),
            created_at=datetime.combine(
                stored_on or day, time(12, 0), tzinfo=clock.SEOUL
            ),
        )
    )
    db_session.commit()


def _unread(client, headers) -> int:
    r = client.get("/v1/notifications/unread-count", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()["unread"]


def _weekly(client, headers) -> dict:
    r = client.get("/v1/me/challenges/weekly", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


def _join(client, headers, request_id: str | None = None):
    body = {} if request_id is None else {"client_request_id": request_id}
    return client.post("/v1/me/challenges/weekly/join", json=body, headers=headers)


def _history(client, headers) -> list[dict]:
    r = client.get("/v1/me/challenges", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


def _balance(client, headers) -> int:
    r = client.get("/v1/users/me/health", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()["activity_points"]


def _ledger(db_session, member_id: str, kind: str) -> list[PointsLedger]:
    db_session.expire_all()
    return list(
        db_session.scalars(
            select(PointsLedger).where(
                PointsLedger.user_id == member_id,
                PointsLedger.kind == kind,
                PointsLedger.source_type == "weekly_challenge",
            )
        ).all()
    )


def _result_notifications(db_session, member_id: str) -> list[Notification]:
    db_session.expire_all()
    return list(
        db_session.scalars(
            select(Notification).where(
                Notification.user_id == member_id,
                Notification.title.like(_RESULT_TITLE),
            )
        ).all()
    )


def _challenge_rows(db_session, member_id: str) -> int:
    db_session.expire_all()
    return db_session.scalar(
        select(func.count())
        .select_from(WeeklyChallenge)
        .where(WeeklyChallenge.user_id == member_id)
    )


# ---- 참가 ----


@pytest.mark.parametrize(
    ("day", "hour", "minute"),
    [(WED, 0, 0), (THU, 10, 0), (SAT, 10, 0), (SUN, 23, 59)],
)
def test_join_is_closed_outside_monday_and_tuesday(
    client, db_session, at, day, hour, minute
):
    member_id, h = _new_member(client, db_session)
    at(day, hour, minute)

    state = _weekly(client, h)
    assert state["joinable"] is False
    assert state["blocked_reason"] == "join_closed"
    assert state["week_start"] == MON.isoformat()
    assert state["week_end"] == SUN.isoformat()
    assert state["join_until"] == TUE.isoformat()

    r = _join(client, h)
    assert r.status_code == 409, r.text
    assert _challenge_rows(db_session, member_id) == 0
    assert _balance(client, h) == 1000


@pytest.mark.parametrize(("day", "hour", "minute"), [(MON, 0, 0), (TUE, 23, 59)])
def test_join_opens_on_monday_and_tuesday_kst(client, db_session, at, day, hour, minute):
    """KST 월요일 0시(UTC 로는 일요일)부터 화요일 끝까지 참가할 수 있다."""
    _, h = _new_member(client, db_session)
    at(day, hour, minute)

    state = _weekly(client, h)
    assert state["joinable"] is True
    assert state["blocked_reason"] is None

    r = _join(client, h)
    assert r.status_code == 201, r.text
    assert r.json()["challenge"]["week_start"] == MON.isoformat()


def test_join_stakes_100_points_and_freezes_goal(client, db_session, at):
    member_id, h = _new_member(client, db_session, points=1000, goal=4)
    at(MON)
    assert _weekly(client, h)["goal"] == 4

    r = _join(client, h)
    assert r.status_code == 201, r.text
    body = r.json()
    challenge = body["challenge"]
    assert body["spent"] == 100
    assert body["balance"] == 900
    assert challenge["goal"] == 4
    assert challenge["stake"] == 100
    assert challenge["reward"] == 200
    assert challenge["status"] == "active"
    assert challenge["progress"] == 0
    assert challenge["rewarded"] == 0
    assert _balance(client, h) == 900

    spends = _ledger(db_session, member_id, "spend")
    assert len(spends) == 1
    assert spends[0].delta == -100
    assert spends[0].reason == "challenge_stake"
    assert spends[0].source_id == challenge["id"]

    # 참가 뒤 목표를 바꿔도 이번 주 챌린지는 참가할 때 목표 그대로다.
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    profile.weekly_workout_goal = 2
    db_session.commit()
    state = _weekly(client, h)
    assert state["goal"] == 4
    assert state["challenge"]["goal"] == 4


@pytest.mark.parametrize(("goal", "expected"), [(None, 3), (0, 3), (5, 5), (10, 7)])
def test_goal_defaults_to_three_and_caps_at_seven(
    client, db_session, at, goal, expected
):
    _, h = _new_member(client, db_session, goal=goal)
    at(TUE)

    assert _weekly(client, h)["goal"] == expected
    r = _join(client, h)
    assert r.status_code == 201, r.text
    assert r.json()["challenge"]["goal"] == expected


def test_join_only_once_per_week(client, db_session, at):
    member_id, h = _new_member(client, db_session)
    at(MON)

    first = _join(client, h, request_id="join-1")
    assert first.status_code == 201, first.text
    # 응답을 못 받고 다시 누른 같은 시도는 새로 걸지 않고 처음 기록을 돌려준다.
    retry = _join(client, h, request_id="join-1")
    assert retry.status_code == 201, retry.text
    assert retry.json()["challenge"]["id"] == first.json()["challenge"]["id"]
    # 다른 시도는 이미 참가했다고 막는다 — 화요일에도 마찬가지다.
    assert _join(client, h, request_id="join-2").status_code == 409
    at(TUE)
    assert _join(client, h).status_code == 409
    state = _weekly(client, h)
    assert state["joinable"] is False
    assert state["blocked_reason"] == "already_joined"

    assert _challenge_rows(db_session, member_id) == 1
    assert len(_ledger(db_session, member_id, "spend")) == 1
    assert _balance(client, h) == 900

    # 다음 주 월요일에는 다시 참가할 수 있다.
    at(NEXT_MON)
    r = _join(client, h)
    assert r.status_code == 201, r.text
    assert r.json()["challenge"]["week_start"] == NEXT_MON.isoformat()
    assert _challenge_rows(db_session, member_id) == 2


def test_join_needs_enough_points(client, db_session, at):
    member_id, h = _new_member(client, db_session, points=60)
    at(MON)

    state = _weekly(client, h)
    assert state["joinable"] is False
    assert state["blocked_reason"] == "insufficient_points"
    assert state["shortfall"] == 40

    r = _join(client, h)
    assert r.status_code == 409, r.text
    assert _challenge_rows(db_session, member_id) == 0
    assert _ledger(db_session, member_id, "spend") == []
    assert _balance(client, h) == 60


def test_trainer_cannot_join(client, db_session, at):
    from app.core.security import create_access_token
    from app.models.models import User

    trainer_id = f"trainer-{uuid4().hex[:10]}"
    db_session.add(
        User(
            id=trainer_id,
            email=f"{trainer_id}@oncare.com",
            name="챌린지 트레이너",
            hashed_password="unused",
            role="trainer",
        )
    )
    db_session.commit()
    at(MON)
    r = client.post(
        "/v1/me/challenges/weekly/join",
        json={},
        headers={"Authorization": f"Bearer {create_access_token(trainer_id)}"},
    )
    assert r.status_code == 403, r.text
    db_session.delete(db_session.get(User, trainer_id))
    db_session.commit()


# ---- 진행 ----


def test_progress_counts_days_with_a_record(client, db_session, at):
    member_id, h = _new_member(client, db_session, goal=3)
    at(MON)
    assert _join(client, h).status_code == 201

    _record(db_session, member_id, MON)
    _record(db_session, member_id, MON)  # 같은 날 두 번은 1회
    _record(db_session, member_id, TUE, source="trainer_pt")  # 출처는 가리지 않는다
    _record(db_session, member_id, MON - timedelta(days=1))  # 지난 주 일요일
    _record(db_session, member_id, THU)  # 아직 오지 않은 날
    at(WED)

    state = _weekly(client, h)
    assert state["progress"] == 2
    assert state["challenge"]["progress"] == 2
    assert state["challenge"]["achieved"] is False

    # 앱 경로로 오늘 기록을 더하면 목표를 채운다. 보상은 주가 끝나야 받는다.
    r = post_exercise(
        client,
        json={
            "type": "cardio",
            "name": "걷기",
            "minutes": 20,
            "calories": 0,
            "date": WED.isoformat(),
        },
        headers=h,
    )
    assert r.status_code == 201, r.text
    state = _weekly(client, h)
    assert state["progress"] == 3
    assert state["challenge"]["achieved"] is True
    assert state["challenge"]["status"] == "active"
    assert state["challenge"]["rewarded"] == 0
    assert _ledger(db_session, member_id, "earn") == []
    assert _result_notifications(db_session, member_id) == []


# ---- 판정 ----


def test_success_rewards_200_once_after_the_week_ends(client, db_session, at):
    member_id, h = _new_member(client, db_session, points=1000, goal=3)
    at(MON)
    assert _join(client, h).status_code == 201
    for day in (MON, WED, SUN):
        _record(db_session, member_id, day)

    # 일요일 밤까지는 판정하지 않는다.
    at(SUN, 23, 59)
    assert _weekly(client, h)["challenge"]["status"] == "active"
    assert _balance(client, h) == 900

    # 월요일 하루는 유예다 — 판정하지 않는다(#3362).
    at(NEXT_MON, 0, 1)
    assert _history(client, h)[0]["status"] == "active"
    assert _balance(client, h) == 900

    at(NEXT_TUE, 0, 1)
    history = _history(client, h)
    last = history[0]
    assert last["week_start"] == MON.isoformat()
    assert last["status"] == "succeeded"
    assert last["progress"] == 3
    assert last["achieved"] is True
    assert last["rewarded"] == 200
    assert last["settled_at"] is not None
    assert _balance(client, h) == 1100

    # 사용처·잔액·알림함·챌린지를 몇 번 읽어도 보상과 알림은 한 번이다.
    for _ in range(2):
        assert client.get("/v1/me/points/shop", headers=h).status_code == 200
        assert client.get("/v1/notifications", headers=h).status_code == 200
        _weekly(client, h)
        _history(client, h)
        assert _balance(client, h) == 1100

    earns = _ledger(db_session, member_id, "earn")
    assert len(earns) == 1
    assert earns[0].delta == 200
    assert earns[0].reason == "challenge_reward"
    assert earns[0].source_id == last["id"]
    notices = _result_notifications(db_session, member_id)
    assert len(notices) == 1
    assert notices[0].title == "주간 챌린지 성공! 200P를 받았어요"
    # 결과는 포인트 사용처로 보낸다 — 다음 주 참가와 돌려받은 포인트가 그 화면에
    # 있다. 내 혜택은 교환해 가진 것(쿠폰·보호권)만 둔다(#1789).
    assert notices[0].category == "points_shop"
    assert "9월 14일 ~ 9월 20일" in notices[0].body

    # 새 주의 상태는 참가 전이다.
    state = _weekly(client, h)
    assert state["week_start"] == NEXT_MON.isoformat()
    assert state["challenge"] is None
    assert state["settling_challenge"] is None
    assert state["joinable"] is True


def test_failure_loses_the_stake(client, db_session, at):
    member_id, h = _new_member(client, db_session, points=1000, goal=3)
    at(MON)
    assert _join(client, h).status_code == 201
    _record(db_session, member_id, MON)
    _record(db_session, member_id, TUE)

    at(NEXT_TUE)
    last = _history(client, h)[0]
    assert last["status"] == "failed"
    assert last["progress"] == 2
    assert last["achieved"] is False
    assert last["rewarded"] == 0
    assert _balance(client, h) == 900
    assert _ledger(db_session, member_id, "earn") == []
    notices = _result_notifications(db_session, member_id)
    assert len(notices) == 1
    assert notices[0].title == "주간 챌린지 목표를 채우지 못했어요"
    assert "3회 중 2회" in notices[0].body

    # 판정 뒤 지난 주 기록을 더해도 결과는 판정 그대로다.
    _record(db_session, member_id, SAT)
    last = _history(client, h)[0]
    assert last["status"] == "failed"
    assert last["progress"] == 2
    assert _balance(client, h) == 900
    assert len(_result_notifications(db_session, member_id)) == 1


@pytest.mark.parametrize(
    ("path", "read_balance"),
    [
        ("/v1/users/me/health", lambda body: body["activity_points"]),
        ("/v1/me/points/shop", lambda body: body["balance"]),
    ],
)
def test_reading_points_settles_the_finished_week(
    client, db_session, at, path, read_balance
):
    member_id, h = _new_member(client, db_session, points=1000, goal=1)
    at(MON)
    assert _join(client, h).status_code == 201
    _record(db_session, member_id, TUE)

    at(NEXT_MON + timedelta(days=2))
    r = client.get(path, headers=h)
    assert r.status_code == 200, r.text
    assert read_balance(r.json()) == 1100
    db_session.expire_all()
    row = db_session.scalar(
        select(WeeklyChallenge).where(WeeklyChallenge.user_id == member_id)
    )
    assert row.status == "succeeded"
    assert row.final_days == 1


def test_reading_notifications_creates_the_result_notice(client, db_session, at):
    member_id, h = _new_member(client, db_session, goal=2)
    at(TUE)
    assert _join(client, h).status_code == 201
    _record(db_session, member_id, TUE)

    at(NEXT_TUE)
    r = client.get("/v1/notifications", headers=h)
    assert r.status_code == 200, r.text
    notices = [n for n in r.json() if n["title"].startswith("주간 챌린지")]
    assert len(notices) == 1
    assert notices[0]["category"] == "points_shop"
    assert notices[0]["action"] == {
        "label": "포인트 사용처 보기",
        "target": "points_shop",
    }

    r = client.get("/v1/notifications", headers=h)
    assert len([n for n in r.json() if n["title"].startswith("주간 챌린지")]) == 1


def test_last_week_reward_lands_before_this_week_join(client, db_session, at):
    """참가가 먼저 지난 주를 판정한다 — 보상으로 채운 잔액으로 다시 참가할 수 있다."""
    member_id, h = _new_member(client, db_session, points=100, goal=1)
    at(MON)
    assert _join(client, h).status_code == 201
    _record(db_session, member_id, MON)

    # 월요일은 지난주의 유예라 보상이 아직 없다 — 잔액이 모자라 참가하지 못한다(#3362).
    at(NEXT_MON)
    assert _join(client, h).status_code == 409
    assert _ledger(db_session, member_id, "earn") == []

    at(NEXT_TUE)
    r = _join(client, h)
    assert r.status_code == 201, r.text
    assert r.json()["balance"] == 100  # 0 + 보상 200 - 이번 주 100
    assert len(_ledger(db_session, member_id, "earn")) == 1
    assert len(_ledger(db_session, member_id, "spend")) == 2


def test_weeks_left_unread_are_settled_later_once(client, db_session, at):
    """몇 주 동안 앱을 열지 않아도 다음에 읽을 때 그 주를 한 번 판정한다."""
    member_id, h = _new_member(client, db_session, goal=1)
    at(MON)
    assert _join(client, h).status_code == 201

    at(NEXT_MON + timedelta(days=14))
    history = _history(client, h)
    assert [c["status"] for c in history] == ["failed"]
    assert len(_result_notifications(db_session, member_id)) == 1
    assert _balance(client, h) == 900


# ---- 유예와 기록 마감 (#3362) ----


def test_the_day_after_the_week_is_a_grace_day(client, db_session, at):
    """주가 끝난 다음 날은 판정하지 않고 집계 중으로 답한다."""
    member_id, h = _new_member(client, db_session, points=1000, goal=3)
    at(MON)
    assert _join(client, h).status_code == 201
    _record(db_session, member_id, MON)
    _record(db_session, member_id, WED)

    # 주 안에서는 집계 중이 아니다.
    at(SUN, 23, 59)
    state = _weekly(client, h)
    assert state["challenge"]["settling"] is False
    assert state["settling_challenge"] is None

    for hour, minute in ((0, 1), (12, 0), (23, 59)):
        at(NEXT_MON, hour, minute)
        # 판정을 부르던 읽기 경로를 모두 지나도 그대로다.
        assert client.get("/v1/me/points/shop", headers=h).status_code == 200
        assert client.get("/v1/notifications", headers=h).status_code == 200
        state = _weekly(client, h)
        assert state["week_start"] == NEXT_MON.isoformat()
        assert state["challenge"] is None
        pending = state["settling_challenge"]
        assert pending["week_start"] == MON.isoformat()
        assert pending["status"] == "active"
        assert pending["settling"] is True
        assert pending["progress"] == 2
        assert pending["settled_at"] is None
        last = _history(client, h)[0]
        assert last["status"] == "active"
        assert last["settling"] is True
        assert _balance(client, h) == 900

    assert _ledger(db_session, member_id, "earn") == []
    assert _result_notifications(db_session, member_id) == []

    at(NEXT_TUE, 0, 0)
    state = _weekly(client, h)
    assert state["settling_challenge"] is None
    last = _history(client, h)[0]
    assert last["status"] == "failed"
    assert last["settling"] is False
    assert len(_result_notifications(db_session, member_id)) == 1


def test_a_record_written_on_the_grace_day_counts(client, db_session, at):
    """일요일 운동을 월요일에 적어도 반영된다 — 그 전에 앱을 열었어도 같다."""
    member_id, h = _new_member(client, db_session, points=1000, goal=3)
    at(MON)
    assert _join(client, h).status_code == 201
    _record(db_session, member_id, MON)
    _record(db_session, member_id, WED)

    # 월요일 아침에 MY 를 먼저 연다. 예전에는 이 순간 실패로 굳었다.
    at(NEXT_MON, 8, 0)
    assert _balance(client, h) == 900
    assert _weekly(client, h)["settling_challenge"]["progress"] == 2

    _record(db_session, member_id, SUN, stored_on=NEXT_MON)
    at(NEXT_MON, 21, 0)
    pending = _weekly(client, h)["settling_challenge"]
    assert pending["progress"] == 3
    assert pending["achieved"] is True
    assert pending["rewarded"] == 0

    at(NEXT_TUE)
    last = _history(client, h)[0]
    assert last["status"] == "succeeded"
    assert last["progress"] == 3
    assert _balance(client, h) == 1100
    assert len(_ledger(db_session, member_id, "earn")) == 1


def test_a_record_written_after_the_grace_day_does_not_count(client, db_session, at):
    """기록 마감은 유예 마지막 날이다 — 판정 요청이 늦게 닿아도 결과가 같다."""
    member_id, h = _new_member(client, db_session, points=1000, goal=3)
    at(MON)
    assert _join(client, h).status_code == 201
    _record(db_session, member_id, MON)
    _record(db_session, member_id, WED)

    # 유예가 끝날 때까지 앱을 열지 않았고, 화요일에 지난주 기록을 먼저 넣었다.
    _record(db_session, member_id, SUN, stored_on=NEXT_TUE)
    at(NEXT_WED)
    last = _history(client, h)[0]
    assert last["status"] == "failed"
    assert last["progress"] == 2
    assert _balance(client, h) == 900
    assert _ledger(db_session, member_id, "earn") == []


def test_a_finished_settlement_is_not_recalculated(client, db_session, at):
    member_id, h = _new_member(client, db_session, points=1000, goal=2)
    at(MON)
    assert _join(client, h).status_code == 201
    _record(db_session, member_id, MON)
    _record(db_session, member_id, TUE)

    at(NEXT_TUE)
    first = _history(client, h)[0]
    assert first["status"] == "succeeded"

    # 판정 뒤 지난주 기록이 사라져도, 날이 더 지나도 결과·보상·알림은 그대로다.
    db_session.expire_all()
    for row in db_session.scalars(
        select(ExerciseSession).where(ExerciseSession.user_id == member_id)
    ).all():
        db_session.delete(row)
    db_session.commit()
    for day in (NEXT_TUE, NEXT_WED, NEXT_MON + timedelta(days=7)):
        at(day)
        again = next(
            c for c in _history(client, h) if c["week_start"] == MON.isoformat()
        )
        assert again["status"] == "succeeded"
        assert again["progress"] == 2
        assert again["settled_at"] == first["settled_at"]
        _unread(client, h)
    assert len(_ledger(db_session, member_id, "earn")) == 1
    assert len(_result_notifications(db_session, member_id)) == 1


def test_joining_this_week_keeps_last_week_settling(client, db_session, at):
    """유예 중에 이번 주에 참가해도 지난주는 집계 중으로 남는다."""
    member_id, h = _new_member(client, db_session, points=1000, goal=1)
    at(MON)
    assert _join(client, h).status_code == 201
    _record(db_session, member_id, MON)

    at(NEXT_MON)
    assert _join(client, h).status_code == 201
    state = _weekly(client, h)
    assert state["challenge"]["week_start"] == NEXT_MON.isoformat()
    assert state["challenge"]["settling"] is False
    assert state["settling_challenge"]["week_start"] == MON.isoformat()
    assert state["settling_challenge"]["settling"] is True
    assert _challenge_rows(db_session, member_id) == 2

    at(NEXT_TUE)
    state = _weekly(client, h)
    assert state["settling_challenge"] is None
    assert state["challenge"]["status"] == "active"
    assert [c["status"] for c in _history(client, h)] == ["active", "succeeded"]


def test_recorded_after_compares_with_the_kst_day_it_was_stored():
    from types import SimpleNamespace

    from app.services import weekly_challenge_service as wcs

    assert wcs.GRACE_DAYS == 1
    assert wcs.record_deadline(MON) == NEXT_MON
    monday_night = datetime.combine(NEXT_MON, time(23, 59), tzinfo=clock.SEOUL)
    assert wcs.recorded_after(SimpleNamespace(created_at=monday_night), NEXT_MON) is False
    tuesday = datetime.combine(NEXT_TUE, time(0, 0), tzinfo=clock.SEOUL)
    assert wcs.recorded_after(SimpleNamespace(created_at=tuesday), NEXT_MON) is True
    # UTC naive 로 저장된 값은 KST 로 옮겨 본다 — 월요일 15:30 UTC 는 화요일 00:30 KST.
    utc_naive = datetime.combine(NEXT_MON, time(15, 30))
    assert wcs.recorded_after(SimpleNamespace(created_at=utc_naive), NEXT_MON) is True
    assert wcs.recorded_after(SimpleNamespace(created_at=None), NEXT_MON) is False


# ---- 미읽음 수 조회의 늦은 생성 (#3362) ----


def test_unread_count_creates_the_result_notice(client, db_session, at):
    """알림함을 열지 않아도 배지 조회가 결과 알림을 만든다."""
    member_id, h = _new_member(client, db_session, goal=1)
    at(MON)
    assert _join(client, h).status_code == 201
    _record(db_session, member_id, MON)

    # 유예 중에는 만들지 않는다.
    at(NEXT_MON, 23, 0)
    before = _unread(client, h)
    assert _result_notifications(db_session, member_id) == []

    at(NEXT_TUE, 0, 1)
    assert _unread(client, h) == before + 1
    notices = _result_notifications(db_session, member_id)
    assert len(notices) == 1
    assert notices[0].read is False
    assert len(_ledger(db_session, member_id, "earn")) == 1

    # 다시 읽어도, 알림함을 열어도 한 건이다.
    at(NEXT_TUE, 9, 0)
    assert _unread(client, h) == before + 1
    assert client.get("/v1/notifications", headers=h).status_code == 200
    assert len(_result_notifications(db_session, member_id)) == 1


def test_unread_count_checks_due_notifications_once_per_interval(
    client, db_session, at, monkeypatch
):
    """배지는 자주 읽는다 — 회원마다 간격에 한 번만 판정·만료 확인을 돌린다."""
    from app.api.v1 import notifications as route

    _, h = _new_member(client, db_session)
    calls: list[str] = []
    monkeypatch.setattr(
        route, "create_due_notifications", lambda db, user_id: calls.append(user_id)
    )

    at(TUE, 10, 0)
    _unread(client, h)
    _unread(client, h)
    at(TUE, 10, 4)
    _unread(client, h)
    assert len(calls) == 1

    at(TUE, 10, 5)
    _unread(client, h)
    assert len(calls) == 2

    # 다른 회원은 따로 센다.
    _, other = _new_member(client, db_session)
    _unread(client, other)
    assert len(calls) == 3
    assert calls[0] == calls[1] != calls[2]


def test_unread_count_also_reminds_expiring_coupons(
    client, db_session, at, monkeypatch
):
    """만료 임박 알림도 같은 자리에서 만든다. 실패해도 배지는 답한다."""
    from app.api.v1 import notifications as route

    member_id, h = _new_member(client, db_session)
    seen: list[str] = []

    def _remind(db, user_id: str) -> int:
        seen.append(user_id)
        raise RuntimeError("boom")

    monkeypatch.setattr(route.points_coupon_service, "remind_expiring", _remind)
    at(WED)
    assert _unread(client, h) >= 0
    assert seen == [member_id]
