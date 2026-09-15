"""연속 기록 보호권 — 교환 한도, 사용 규칙, 연속 일수 반영, 합계 불변. (#1788)

연속 일수 계산 두 개는 DB 없이 돈다. 나머지는 DB 필요(로컬 skip, CI 실행).

"오늘" 을 목요일(2026-09-17, KST)로 고정한다. 이번 주 월요일은 9월 14일, 보호할 수
있는 어제는 9월 16일(수)이다. 요일에 매인 규칙(월요일에는 지난 일요일을 보호하지
않는다)을 실행 요일과 상관없이 재려는 것이다. 새로 가입한 회원으로 확인해 다른
테스트의 기록·포인트와 섞이지 않게 한다.
"""
from __future__ import annotations

from datetime import datetime
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core import clock
from app.core.security import create_access_token
from app.models.models import (
    HealthProfile,
    PointsLedger,
    TrainerClient,
    TrainerProfile,
    User,
)
from app.services.exercise_service import _longest_streak, build_current_week

#: 고정한 오늘(목)과 다음 주 월요일.
THURSDAY = datetime(2026, 9, 17, 10, 0, tzinfo=clock.SEOUL)
NEXT_MONDAY = datetime(2026, 9, 21, 10, 0, tzinfo=clock.SEOUL)
MONDAY = "2026-09-14"
TUESDAY = "2026-09-15"
YESTERDAY = "2026-09-16"
TODAY = "2026-09-17"


@pytest.fixture
def thursday(monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: THURSDAY)


# ---- 연속 일수 (DB 없음) ----


def test_longest_streak_counts_protected_days_as_active():
    daily = [30, 0, 20, 0, 0, 0, 0]
    protected = [False, True, False, False, False, False, False]

    assert _longest_streak(daily) == 1
    assert _longest_streak(daily, protected) == 3
    # 보호한 날만 있어도 그날은 이어진 하루다.
    assert _longest_streak([0] * 7, [False, False, True, True, False, False, False]) == 2


def test_week_totals_ignore_protected_days():
    data = build_current_week(
        [], protected_days=[False, True, False, False, False, False, False]
    )

    assert data["streak_days"] == 1
    assert data["protected_days"] == [False, True, False, False, False, False, False]
    assert data["total_minutes"] == 0
    assert data["total_calories"] == 0
    assert data["daily_minutes"] == [0] * 7
    assert data["sessions"] == []


# ---- 도우미 ----


def _new_member(client, db_session, points: int = 0) -> tuple[str, dict[str, str]]:
    email = f"shd-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    member_id = client.get("/v1/users/me", headers=headers).json()["id"]
    db_session.expire_all()
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    if profile is None:
        db_session.add(HealthProfile(user_id=member_id, activity_points=points))
    else:
        profile.activity_points = points
    db_session.commit()
    return member_id, headers


def _exchange(client, headers, request_id: str | None = None):
    body: dict[str, str] = {"item": "streak_shield"}
    if request_id is not None:
        body["client_request_id"] = request_id
    return client.post("/v1/me/points/exchange", json=body, headers=headers)


def _use(client, headers, day: str):
    return client.post(
        "/v1/me/streak-shields/use", json={"date": day}, headers=headers
    )


def _shields(client, headers) -> dict:
    r = client.get("/v1/me/streak-shields", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


def _add_exercise(client, headers, day: str, minutes: int = 30) -> None:
    r = client.post(
        "/v1/exercise/sessions",
        json={
            "type": "cardio",
            "name": "걷기",
            "minutes": minutes,
            "calories": 0,
            "date": day,
        },
        headers=headers,
    )
    assert r.status_code == 201, r.text


def _week(client, headers, week_start: str | None = None) -> dict:
    params = {"week_start": week_start} if week_start else None
    r = client.get("/v1/exercise/weeks/current", params=params, headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


def _shop_item(client, headers) -> dict:
    r = client.get("/v1/me/points/shop", headers=headers)
    assert r.status_code == 200, r.text
    return next(i for i in r.json()["items"] if i["id"] == "streak_shield")


def _balance(client, headers) -> int:
    return client.get("/v1/users/me/health", headers=headers).json()["activity_points"]


# ---- 교환 ----


def test_shop_lists_streak_shield(client, db_session, thursday):
    _, rich = _new_member(client, db_session, points=1000)
    _, poor = _new_member(client, db_session, points=100)

    item = _shop_item(client, rich)
    assert (item["cost"], item["valid_days"], item["redeemer"]) == (300, 0, "member")
    assert item["available"] is True
    assert item["blocked_reason"] is None

    item = _shop_item(client, poor)
    assert item["available"] is False
    assert item["blocked_reason"] == "insufficient_points"
    assert item["shortfall"] == 200


def test_exchange_spends_300_and_holds_at_most_two(client, db_session, thursday):
    member_id, h = _new_member(client, db_session, points=1000)

    first = _exchange(client, h)
    assert first.status_code == 201, first.text
    body = first.json()
    assert body["coupon"] is None
    assert body["shield"]["status"] == "held"
    assert body["shield"]["protected_on"] is None
    assert (body["spent"], body["balance"]) == (300, 700)

    assert _exchange(client, h).status_code == 201
    third = _exchange(client, h)
    assert third.status_code == 409, third.text
    assert _balance(client, h) == 400

    item = _shop_item(client, h)
    assert item["available"] is False
    assert item["blocked_reason"] == "shield_limit"
    assert item["shortfall"] == 0

    spends = db_session.scalars(
        select(PointsLedger).where(
            PointsLedger.user_id == member_id,
            PointsLedger.source_type == "streak_shield",
        )
    ).all()
    assert sorted((row.kind, row.delta, row.reason) for row in spends) == [
        ("spend", -300, "streak_shield"),
        ("spend", -300, "streak_shield"),
    ]
    assert _shields(client, h)["held"] == 2


def test_exchange_retry_with_same_request_id_spends_once(client, db_session, thursday):
    _, h = _new_member(client, db_session, points=1000)

    first = _exchange(client, h, request_id="shield-retry-1")
    again = _exchange(client, h, request_id="shield-retry-1")

    assert first.status_code == 201 and again.status_code == 201
    assert first.json()["shield"]["id"] == again.json()["shield"]["id"]
    assert _balance(client, h) == 700
    assert _shields(client, h)["held"] == 1


# ---- 사용 ----


def test_use_joins_yesterday_to_streak_without_touching_totals(
    client, db_session, monkeypatch
):
    monkeypatch.setattr(clock, "now", lambda: THURSDAY)
    _, h = _new_member(client, db_session, points=1000)
    assert _exchange(client, h).status_code == 201
    assert _exchange(client, h).status_code == 201
    _add_exercise(client, h, MONDAY)
    _add_exercise(client, h, TUESDAY, minutes=40)
    _add_exercise(client, h, TODAY, minutes=20)

    before = _week(client, h)
    assert before["streak_days"] == 2
    assert before["protected_days"] == [False] * 7
    assert before["streak_shield"] == {"held": 2, "protectable_date": YESTERDAY}

    r = _use(client, h, YESTERDAY)
    assert r.status_code == 200, r.text
    assert r.json()["held"] == 1
    assert [u["date"] for u in r.json()["used"]] == [YESTERDAY]

    after = _week(client, h)
    assert after["streak_days"] == 4
    assert after["protected_days"] == [False, False, True, False, False, False, False]
    assert after["streak_shield"] == {"held": 1, "protectable_date": None}
    # 보호한 날은 운동한 날이 아니다 — 합계·요일별 값·기록 목록이 그대로다.
    for key in (
        "total_minutes",
        "total_calories",
        "daily_minutes",
        "daily_calories",
        "sessions",
    ):
        assert after[key] == before[key], key

    # 같은 날을 다시 보호해도 보호권을 더 쓰지 않는다.
    again = _use(client, h, YESTERDAY)
    assert again.status_code == 200, again.text
    status = _shields(client, h)
    assert status["held"] == 1
    assert (status["max_held"], status["cost"]) == (2, 300)
    assert [u["date"] for u in status["used"]] == [YESTERDAY]

    # 주가 바뀌면 지난 주 조회는 보호한 날과 연속 일수를 그대로 보여 주고, 보호권
    # 상태는 싣지 않는다.
    monkeypatch.setattr(clock, "now", lambda: NEXT_MONDAY)
    past = _week(client, h, week_start=MONDAY)
    assert past["streak_days"] == 4
    assert past["protected_days"][2] is True
    assert past["streak_shield"] is None


def test_use_only_protects_yesterday_without_exercise(client, db_session, thursday):
    _, h = _new_member(client, db_session, points=300)
    assert _exchange(client, h).status_code == 201

    for day in (TODAY, TUESDAY, "2026-09-18"):
        r = _use(client, h, day)
        assert r.status_code == 409, (day, r.text)

    _add_exercise(client, h, YESTERDAY)
    assert _week(client, h)["streak_shield"] == {"held": 1, "protectable_date": None}
    r = _use(client, h, YESTERDAY)
    assert r.status_code == 409, r.text

    assert _shields(client, h)["held"] == 1


def test_use_without_shield_is_rejected(client, db_session, thursday):
    _, h = _new_member(client, db_session)

    assert _week(client, h)["streak_shield"] == {"held": 0, "protectable_date": None}
    r = _use(client, h, YESTERDAY)
    assert r.status_code == 409, r.text
    assert _week(client, h)["protected_days"] == [False] * 7


def test_monday_does_not_protect_last_sunday(client, db_session, monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: NEXT_MONDAY)
    _, h = _new_member(client, db_session, points=300)
    assert _exchange(client, h).status_code == 201

    # 어제(일요일)는 지난주다 — 이번 주 연속 일수에 이어지지 않아 보호권을 쓰지 않는다.
    assert _week(client, h)["streak_shield"] == {"held": 1, "protectable_date": None}
    r = _use(client, h, "2026-09-20")
    assert r.status_code == 409, r.text
    assert _shields(client, h)["held"] == 1


def _make_linked_trainer(db_session, member_id: str) -> str:
    """이 테스트만 쓰는 트레이너를 만들어 회원을 담당으로 붙인다."""
    trainer_id = f"trainer-{uuid4().hex[:10]}"
    db_session.add(
        User(
            id=trainer_id,
            email=f"{trainer_id}@oncare.com",
            name="보호권 트레이너",
            hashed_password="unused",
            role="trainer",
        )
    )
    db_session.commit()
    db_session.add(TrainerProfile(trainer_id=trainer_id, gym_name="보호권짐"))
    db_session.add(
        TrainerClient(
            id=f"tc-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            active=True,
        )
    )
    db_session.commit()
    return trainer_id


def _drop_user(db_session, user_id: str) -> None:
    db_session.rollback()
    db_session.expire_all()
    user = db_session.get(User, user_id)
    if user is not None:
        db_session.delete(user)
        db_session.commit()


def _sessions_on(client, headers, day: str) -> list[str]:
    return [s["id"] for s in _week(client, headers)["sessions"] if s["date"] == day]


# ---- 운동한 날의 보호권 되돌리기 ----


def test_exercise_on_protected_day_refunds_shield(client, db_session, thursday):
    _, h = _new_member(client, db_session, points=300)
    assert _exchange(client, h).status_code == 201
    _add_exercise(client, h, TUESDAY)
    assert _use(client, h, YESTERDAY).status_code == 200
    assert _shields(client, h)["held"] == 0

    _add_exercise(client, h, YESTERDAY)

    status = _shields(client, h)
    assert (status["held"], status["used"]) == (1, [])
    week = _week(client, h)
    assert week["protected_days"] == [False] * 7
    assert week["streak_days"] == 2  # 화·수 — 수요일은 이제 실제로 운동한 날이다.

    # 같은 날을 더 기록해도 더 돌려주지 않는다.
    _add_exercise(client, h, YESTERDAY, minutes=10)
    assert _shields(client, h)["held"] == 1

    # 기록을 지워도 보호는 다시 걸리지 않는다.
    for session_id in _sessions_on(client, h, YESTERDAY):
        assert client.delete(
            f"/v1/exercise/sessions/{session_id}", headers=h
        ).status_code == 200
    week = _week(client, h)
    assert week["protected_days"] == [False] * 7
    assert week["streak_days"] == 1
    assert _shields(client, h)["held"] == 1


def test_refund_may_exceed_hold_limit(client, db_session, thursday):
    _, h = _new_member(client, db_session, points=1000)
    assert _exchange(client, h).status_code == 201
    assert _use(client, h, YESTERDAY).status_code == 200
    assert _exchange(client, h).status_code == 201
    assert _exchange(client, h).status_code == 201
    assert _shields(client, h)["held"] == 2

    _add_exercise(client, h, YESTERDAY)

    # 최대 보유 수는 교환의 규칙이다 — 돌려받아 3개가 되고, 그동안 교환은 막힌다.
    assert _shields(client, h)["held"] == 3
    assert _week(client, h)["streak_shield"] == {"held": 3, "protectable_date": None}
    item = _shop_item(client, h)
    assert (item["available"], item["blocked_reason"]) == (False, "shield_limit")
    assert _exchange(client, h).status_code == 409


def test_moving_record_onto_protected_day_refunds_shield(client, db_session, thursday):
    _, h = _new_member(client, db_session, points=300)
    assert _exchange(client, h).status_code == 201
    _add_exercise(client, h, TUESDAY)
    assert _use(client, h, YESTERDAY).status_code == 200
    (session_id,) = _sessions_on(client, h, TUESDAY)

    r = client.put(
        f"/v1/exercise/sessions/{session_id}",
        json={"type": "cardio", "name": "걷기", "minutes": 30, "date": YESTERDAY},
        headers=h,
    )

    assert r.status_code == 200, r.text
    assert _shields(client, h)["held"] == 1
    assert _week(client, h)["protected_days"][2] is False


def test_routine_completion_on_protected_day_refunds_shield(
    client, db_session, monkeypatch
):
    from app.models.models import TrainerRoutine

    monkeypatch.setattr(clock, "now", lambda: THURSDAY)
    member_id, h = _new_member(client, db_session, points=300)
    assert _exchange(client, h).status_code == 201
    assert _use(client, h, YESTERDAY).status_code == 200
    routine_id = f"rt-shd-{uuid4().hex[:10]}"
    db_session.add(
        TrainerRoutine(
            id=routine_id,
            trainer_id=None,
            member_id=member_id,
            name="걷기",
            minutes=20,
            type="유산소",
            source="ai",
            status="approved",
        )
    )
    db_session.commit()

    # 자정 직전에 시작한 완료 요청이 보호보다 늦게 커밋된 경우 — 완료 시각이 보호한
    # 날로 찍힌다. 시계를 되돌려 흉내 낸다.
    monkeypatch.setattr(
        clock, "now", lambda: datetime(2026, 9, 16, 23, 59, tzinfo=clock.SEOUL)
    )
    r = client.post(
        f"/v1/me/coach/routines/{routine_id}/complete",
        json={"minutes": 20, "intensity": "moderate", "member_note": ""},
        headers=h,
    )
    assert r.status_code == 200, r.text

    monkeypatch.setattr(clock, "now", lambda: THURSDAY)
    assert _shields(client, h)["held"] == 1
    assert _week(client, h)["protected_days"][2] is False


def test_trainer_pt_completion_on_protected_day_refunds_shield(
    client, db_session, thursday
):
    member_id, h = _new_member(client, db_session, points=300)
    assert _exchange(client, h).status_code == 201
    assert _use(client, h, YESTERDAY).status_code == 200
    trainer_id = _make_linked_trainer(db_session, member_id)
    th = {"Authorization": f"Bearer {create_access_token(trainer_id)}"}
    try:
        created = client.post(
            "/v1/trainer/schedule",
            json={
                "date": YESTERDAY,
                "time": "20:00",
                "client_name": "u",
                "member_id": member_id,
                "type": "1:1 PT",
                "duration_minutes": 45,
            },
            headers=th,
        )
        assert created.status_code == 201, created.text
        session_id = created.json()["id"]
        done = client.post(
            f"/v1/trainer/schedule/{session_id}/complete", json={}, headers=th
        )
        assert done.status_code == 200, done.text

        assert _shields(client, h)["held"] == 1
        week = _week(client, h)
        assert week["protected_days"][2] is False
        assert f"sched-ex-{session_id}" in [s["id"] for s in week["sessions"]]

        # 트레이너가 세션을 지워 파생 기록이 사라져도 보호는 다시 걸리지 않는다.
        client.delete(f"/v1/trainer/schedule/{session_id}", headers=th)
        assert _week(client, h)["protected_days"][2] is False
        assert _shields(client, h)["held"] == 1
    finally:
        _drop_user(db_session, trainer_id)


def test_trainer_week_counts_protected_day(client, db_session, thursday):
    member_id, h = _new_member(client, db_session, points=300)
    trainer_id = f"trainer-{uuid4().hex[:10]}"
    db_session.add(
        User(
            id=trainer_id,
            email=f"{trainer_id}@oncare.com",
            name="보호권 트레이너",
            hashed_password="unused",
            role="trainer",
        )
    )
    db_session.commit()
    db_session.add(TrainerProfile(trainer_id=trainer_id, gym_name="보호권짐"))
    db_session.add(
        TrainerClient(
            id=f"tc-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            active=True,
        )
    )
    db_session.commit()
    try:
        assert _exchange(client, h).status_code == 201
        _add_exercise(client, h, TUESDAY)
        _add_exercise(client, h, TODAY)
        assert _use(client, h, YESTERDAY).status_code == 200

        r = client.get(
            f"/v1/trainer/clients/{member_id}/exercise-week",
            headers={"Authorization": f"Bearer {create_access_token(trainer_id)}"},
        )
        assert r.status_code == 200, r.text
        assert r.json()["streak_days"] == 3
        assert r.json()["protected_days"][2] is True
        assert r.json()["streak_shield"] is None
    finally:
        db_session.rollback()
        db_session.expire_all()
        trainer = db_session.get(User, trainer_id)
        if trainer is not None:
            db_session.delete(trainer)
            db_session.commit()
