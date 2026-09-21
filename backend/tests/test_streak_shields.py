"""연속 기록 보호권 — 교환 한도, 사용 규칙, 기록 연속 반영. (#1788)

보호권이 지키는 것은 **기록 연속**이다: 식단 한 끼든 운동 한 건이든 남긴 날이
이어진 길이(`record_activity.record_streak_days`). 운동 탭의 `N일 연속 운동`
(`exercise_service._longest_streak`)은 운동만 세고 보호한 날을 넣지 않는다 —
여기서도 그 둘이 서로를 건드리지 않는지 함께 본다.

연속 일수 계산 하나는 DB 없이 돈다. 나머지는 DB 필요(로컬 skip, CI 실행).

"오늘" 을 목요일(2026-09-17, KST)로 고정한다. 보호할 수 있는 어제는 9월 16일(수)
이다. 실행 요일과 상관없이 날짜에 매인 규칙을 재려는 것이다. 새로 가입한 회원으로
확인해 다른 테스트의 기록·포인트와 섞이지 않게 한다.
"""
from __future__ import annotations

from datetime import datetime
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core import clock
from app.core.security import create_access_token
from app.models.models import (
    DietEntry,
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


def test_longest_streak_counts_exercise_only():
    # 운동 탭의 연속은 운동만 센다 — 보호권도 식단도 여기에는 들어가지 않는다.
    assert _longest_streak([30, 0, 20, 0, 0, 0, 0]) == 1
    assert _longest_streak([30, 20, 20, 0, 0, 0, 0]) == 3
    assert _longest_streak([0] * 7) == 0


def test_exercise_week_has_no_shield_fields():
    # 보호권은 운동 주간 응답에 실리지 않는다 — 쓰는 자리는 포인트 화면이다(#2075).
    data = build_current_week([])

    assert "protected_days" not in data
    assert "streak_shield" not in data
    assert data["streak_days"] == 0


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


def _add_diet(db_session, member_id: str, day: str) -> None:
    """그날 끼니 한 건. 사진 분석을 타지 않고 행만 넣는다 — 기록 여부만 보면 된다."""
    db_session.add(
        DietEntry(
            id=f"diet-shd-{uuid4().hex[:10]}",
            user_id=member_id,
            date=day,
            meal_type="lunch",
            time_label="12:00",
            total_calories=500,
        )
    )
    db_session.commit()


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
    assert (item["cost"], item["valid_days"]) == (300, 0)
    assert "redeemer" not in item
    assert item["available"] is True
    assert item["blocked_reason"] is None

    item = _shop_item(client, poor)
    assert item["available"] is False
    assert item["blocked_reason"] == "insufficient_points"
    assert item["shortfall"] == 200


def test_exchange_spends_300_and_holds_at_most_four(client, db_session, thursday):
    member_id, h = _new_member(client, db_session, points=2000)

    first = _exchange(client, h)
    assert first.status_code == 201, first.text
    body = first.json()
    assert body["coupon"] is None
    assert body["shield"]["status"] == "held"
    assert body["shield"]["protected_on"] is None
    assert (body["spent"], body["balance"]) == (300, 1700)

    for _ in range(3):
        assert _exchange(client, h).status_code == 201
    fifth = _exchange(client, h)
    assert fifth.status_code == 409, fifth.text
    assert _balance(client, h) == 800

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
    ] * 4
    assert _shields(client, h)["held"] == 4


def test_exchange_retry_with_same_request_id_spends_once(client, db_session, thursday):
    _, h = _new_member(client, db_session, points=1000)

    first = _exchange(client, h, request_id="shield-retry-1")
    again = _exchange(client, h, request_id="shield-retry-1")

    assert first.status_code == 201 and again.status_code == 201
    assert first.json()["shield"]["id"] == again.json()["shield"]["id"]
    assert _balance(client, h) == 700
    assert _shields(client, h)["held"] == 1


# ---- 사용 ----


def test_use_joins_yesterday_to_record_streak_only(client, db_session, monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: THURSDAY)
    _, h = _new_member(client, db_session, points=1000)
    assert _exchange(client, h).status_code == 201
    assert _exchange(client, h).status_code == 201
    _add_exercise(client, h, MONDAY)
    _add_exercise(client, h, TUESDAY, minutes=40)
    _add_exercise(client, h, TODAY, minutes=20)

    before = _week(client, h)
    before_status = _shields(client, h)
    # 월·화는 이어졌고 수(어제)가 비어 오늘만 남았다 — 기록 연속은 1.
    assert before["streak_days"] == 2
    assert before_status["record_streak_days"] == 1
    # 창은 어제부터 거슬러 30일이다 — 어느 칸이 실제로 비었는지는 달력이 가린다.
    assert (before_status["held"], before_status["protectable_to"]) == (2, YESTERDAY)
    assert before_status["protectable_from"] == "2026-08-18"

    r = _use(client, h, YESTERDAY)
    assert r.status_code == 200, r.text
    assert r.json()["held"] == 1
    assert [u["date"] for u in r.json()["used"]] == [YESTERDAY]
    # 보호권이 이어 붙인 것은 기록 연속뿐이다: 월·화·수(보호)·목.
    assert r.json()["record_streak_days"] == 4

    after = _week(client, h)
    # 운동 탭의 연속은 그대로 2 다 — 보호한 날은 운동한 날이 아니다.
    assert after["streak_days"] == 2
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
    assert (status["max_held"], status["cost"]) == (4, 300)
    assert [u["date"] for u in status["used"]] == [YESTERDAY]


def test_use_protects_any_empty_day_in_the_window(client, db_session, thursday):
    """보호할 수 있는 날은 어제부터 거슬러 30일 안의 **빈** 날이다. (#2075)

    어제 하나만 열어 두면 어제를 놓친 뒤에 산 보호권은 쓸 데가 없다. 대신 창을
    30일로 묶어, 몇 달 전 기록까지 칠해 연속 숫자가 가벼워지지 않게 한다.
    """
    _, h = _new_member(client, db_session, points=900)
    for _ in range(3):
        assert _exchange(client, h).status_code == 201

    # 오늘·미래·창보다 오래된 날은 막힌다.
    for day in (TODAY, "2026-09-18", "2026-08-17"):
        r = _use(client, h, day)
        assert r.status_code == 409, (day, r.text)

    # 창 안이고 비어 있으면 어제가 아니어도 보호한다 — 창의 첫날과 며칠 전.
    assert _use(client, h, "2026-08-18").status_code == 200
    assert _use(client, h, "2026-09-10").status_code == 200

    # 기록이 있는 날은 창 안이어도 보호하지 않는다.
    _add_exercise(client, h, YESTERDAY)
    r = _use(client, h, YESTERDAY)
    assert r.status_code == 409, r.text

    assert _shields(client, h)["held"] == 1


def test_diet_alone_makes_the_day_recorded(client, db_session, thursday):
    """식단 한 끼만 있어도 그날은 기록한 날이다 — 보호할 수 없고 연속은 이어진다."""
    member_id, h = _new_member(client, db_session, points=300)
    assert _exchange(client, h).status_code == 201
    _add_diet(db_session, member_id, YESTERDAY)

    status = _shields(client, h)
    # 어제는 식단으로 이미 기록한 날이라 보호 대상이 아니다.
    assert status["record_streak_days"] == 1
    r = _use(client, h, YESTERDAY)
    assert r.status_code == 409, r.text

    # 운동 탭의 연속은 식단을 세지 않는다.
    assert _week(client, h)["streak_days"] == 0


def test_monday_protects_last_sunday(client, db_session, monkeypatch):
    """기록 연속은 주 단위가 아니다 — 월요일에도 어제(일요일)를 보호한다."""
    monkeypatch.setattr(clock, "now", lambda: NEXT_MONDAY)
    _, h = _new_member(client, db_session, points=300)
    assert _exchange(client, h).status_code == 201

    assert _shields(client, h)["protectable_to"] == "2026-09-20"
    r = _use(client, h, "2026-09-20")
    assert r.status_code == 200, r.text
    assert r.json()["held"] == 0
    assert r.json()["record_streak_days"] == 1


def test_use_without_shield_is_rejected(client, db_session, thursday):
    _, h = _new_member(client, db_session)

    status = _shields(client, h)
    # 보호권이 없으면 창도 비운다.
    assert (status["held"], status["protectable_from"]) == (0, None)
    assert status["protectable_to"] is None
    r = _use(client, h, YESTERDAY)
    assert r.status_code == 409, r.text
    assert _shields(client, h)["used"] == []




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
    # 수요일은 이제 실제로 운동한 날이라 운동 연속도 화·수로 이어진다.
    assert _week(client, h)["streak_days"] == 2

    # 같은 날을 더 기록해도 더 돌려주지 않는다.
    _add_exercise(client, h, YESTERDAY, minutes=10)
    assert _shields(client, h)["held"] == 1

    # 기록을 지워도 보호는 다시 걸리지 않는다.
    for session_id in _sessions_on(client, h, YESTERDAY):
        assert client.delete(
            f"/v1/exercise/sessions/{session_id}", headers=h
        ).status_code == 200
    assert _week(client, h)["streak_days"] == 1
    status = _shields(client, h)
    assert (status["held"], status["used"]) == (1, [])


def test_refund_may_exceed_hold_limit(client, db_session, thursday):
    _, h = _new_member(client, db_session, points=2000)
    assert _exchange(client, h).status_code == 201
    assert _use(client, h, YESTERDAY).status_code == 200
    for _ in range(4):
        assert _exchange(client, h).status_code == 201
    assert _shields(client, h)["held"] == 4

    _add_exercise(client, h, YESTERDAY)

    # 최대 보유 수는 교환의 규칙이다 — 돌려받아 5개가 되고, 그동안 교환은 막힌다.
    status = _shields(client, h)
    assert status["held"] == 5
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
    status = _shields(client, h)
    assert (status["held"], status["used"]) == (1, [])


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
    status = _shields(client, h)
    assert (status["held"], status["used"]) == (1, [])


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

        status = _shields(client, h)
        assert (status["held"], status["used"]) == (1, [])
        week = _week(client, h)
        assert f"sched-ex-{session_id}" in [s["id"] for s in week["sessions"]]

        # 트레이너가 세션을 지워 파생 기록이 사라져도 보호는 다시 걸리지 않는다.
        client.delete(f"/v1/trainer/schedule/{session_id}", headers=th)
        assert _shields(client, h)["used"] == []
    finally:
        _drop_user(db_session, trainer_id)


def test_trainer_week_ignores_protected_day(client, db_session, thursday):
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
        # 트레이너가 보는 연속도 운동만 센다 — 보호한 수요일은 끊긴 자리다.
        assert r.json()["streak_days"] == 1
        assert "protected_days" not in r.json()
        assert "streak_shield" not in r.json()
    finally:
        db_session.rollback()
        db_session.expire_all()
        trainer = db_session.get(User, trainer_id)
        if trainer is not None:
            db_session.delete(trainer)
            db_session.commit()
