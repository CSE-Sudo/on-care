"""추천 개인운동은 매일 새로 체크하는 목록이다. (#2161) DB 필요.

트레이너가 목록을 바꾸기 전까지 같은 목록이 날마다 미완료로 다시 시작한다.
여기서 지키는 계약:

1. 완료는 하루 단위다 — 어제 한 운동이 오늘 체크된 채로 보이지 않고, 오늘 다시
   완료할 수 있다.
2. 지난 날짜는 그날 걸려 있던 목록과 그날 완료를 그대로 보여 준다 — 트레이너가
   나중에 철회해도 그날 목록은 남는다.
3. 완료·해제는 오늘만 건드린다.
"""
from __future__ import annotations

from datetime import datetime, timedelta
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core import clock
from app.db.session import SessionLocal
from app.models.models import (
    AiConversation,
    ExerciseSession,
    TrainerClient,
    TrainerRoutine,
)

MEMBER_ID = "user-jisu"


def _h(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login", data={"username": email, "password": "oncare123"}
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _move_to(monkeypatch, moment: datetime) -> None:
    """서버의 '지금' 을 옮긴다. `today()`·`today_iso()` 도 이것을 따라간다."""
    monkeypatch.setattr(clock, "now", lambda: moment)


def _cleanup(routine_ids: list[str]) -> None:
    db = SessionLocal()
    try:
        for row in db.scalars(
            select(ExerciseSession).where(
                ExerciseSession.assigned_routine_id.in_(routine_ids)
            )
        ).all():
            db.delete(row)
        for routine_id in routine_ids:
            row = db.get(TrainerRoutine, routine_id)
            if row is not None:
                db.delete(row)
        db.commit()
    finally:
        db.close()


@pytest.fixture()
def today() -> datetime:
    """이 테스트의 '오늘' — 실제 오늘 정오(KST). 날짜 경계에서 흔들리지 않게 정오다."""
    now = clock.now()
    return now.replace(hour=12, minute=0, second=0, microsecond=0)


@pytest.fixture()
def assigned(client, today, monkeypatch):
    """트레이너가 오늘 배정한 개인운동 하나. 끝나면 완료 기록과 함께 지운다."""
    _move_to(monkeypatch, today)
    trainer = _login(client, "trainer@oncare.com")
    created = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/routines",
        headers=_h(trainer),
        json={
            "name": f"매일 체크 {uuid4().hex[:6]}",
            "minutes": 20,
            "type": "유산소",
            "reason": "매일 리셋 테스트",
        },
    )
    assert created.status_code == 201, created.text
    routine = created.json()
    yield trainer, routine
    _cleanup([routine["id"]])


def _mine(client, member: str, day=None) -> dict[str, dict]:
    params = {"date": day.isoformat()} if day is not None else None
    res = client.get("/v1/me/coach/routines", headers=_h(member), params=params)
    assert res.status_code == 200, res.text
    return {row["id"]: row for row in res.json()}


def _complete(client, member: str, routine_id: str, minutes: int = 20):
    res = client.post(
        f"/v1/me/coach/routines/{routine_id}/complete",
        headers=_h(member),
        json={"minutes": minutes, "intensity": "moderate"},
    )
    assert res.status_code == 200, res.text
    return res.json()


def _completions(routine_id: str) -> list[ExerciseSession]:
    db = SessionLocal()
    try:
        return list(
            db.scalars(
                select(ExerciseSession)
                .where(ExerciseSession.assigned_routine_id == routine_id)
                .order_by(ExerciseSession.completed_at)
            ).all()
        )
    finally:
        db.close()


def test_the_list_starts_unchecked_again_the_next_day(
    client, assigned, today, monkeypatch
):
    _, routine = assigned
    member = _login(client, "jisu@oncare.com")

    assert _complete(client, member, routine["id"])["completed"] is True
    assert _mine(client, member)[routine["id"]]["completed"] is True

    _move_to(monkeypatch, today + timedelta(days=1))

    # 같은 배정이 다음 날 목록에 그대로 있고, 체크는 풀려 있다.
    tomorrow = _mine(client, member)
    assert routine["id"] in tomorrow
    assert tomorrow[routine["id"]]["completed"] is False


def test_the_same_routine_can_be_completed_once_a_day(
    client, assigned, today, monkeypatch
):
    _, routine = assigned
    member = _login(client, "jisu@oncare.com")

    _complete(client, member, routine["id"], minutes=20)
    # 같은 날 다시 누르면 같은 기록이다(더블 탭·재전송).
    _complete(client, member, routine["id"], minutes=5)
    assert len(_completions(routine["id"])) == 1

    _move_to(monkeypatch, today + timedelta(days=1))
    _complete(client, member, routine["id"], minutes=25)

    rows = _completions(routine["id"])
    assert len(rows) == 2
    assert [row.minutes for row in rows] == [20, 25]
    assert rows[0].day_label != rows[1].day_label


def test_a_past_day_shows_that_days_completion(
    client, assigned, today, monkeypatch
):
    _, routine = assigned
    member = _login(client, "jisu@oncare.com")
    _complete(client, member, routine["id"])

    _move_to(monkeypatch, today + timedelta(days=1))

    yesterday = _mine(client, member, today.date())
    assert yesterday[routine["id"]]["completed"] is True
    assert yesterday[routine["id"]]["completed_minutes"] == 20
    assert _mine(client, member)[routine["id"]]["completed"] is False


def test_a_day_before_the_assignment_does_not_list_it(client, assigned, today):
    _, routine = assigned
    member = _login(client, "jisu@oncare.com")

    before = _mine(client, member, today.date() - timedelta(days=1))

    # 배정 전날에는 걸려 있지 않았다 — 안 한 운동으로 보이면 안 된다.
    assert routine["id"] not in before


def test_a_future_day_is_rejected(client, assigned, today):
    member = _login(client, "jisu@oncare.com")

    res = client.get(
        "/v1/me/coach/routines",
        headers=_h(member),
        params={"date": (today.date() + timedelta(days=1)).isoformat()},
    )

    assert res.status_code == 422, res.text


def test_withdrawing_keeps_the_days_it_was_on_the_list(
    client, assigned, today, monkeypatch
):
    trainer, routine = assigned
    member = _login(client, "jisu@oncare.com")
    _complete(client, member, routine["id"])

    _move_to(monkeypatch, today + timedelta(days=1))
    removed = client.delete(
        f"/v1/trainer/clients/{MEMBER_ID}/routines/{routine['id']}",
        headers=_h(trainer),
    )
    assert removed.status_code == 200, removed.text

    # 오늘 목록에서는 바로 빠지고, 트레이너 배정 목록에서도 빠진다.
    assert routine["id"] not in _mine(client, member)
    assigned_now = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/routines", headers=_h(trainer)
    ).json()
    assert routine["id"] not in {row["id"] for row in assigned_now}
    # 걸려 있던 어제는 그대로 남는다 — 한 운동이 지워지지 않는다.
    yesterday = _mine(client, member, today.date())
    assert yesterday[routine["id"]]["completed"] is True

    # 이미 내려온 배정을 다시 철회하면 없는 배정이다.
    again = client.delete(
        f"/v1/trainer/clients/{MEMBER_ID}/routines/{routine['id']}",
        headers=_h(trainer),
    )
    assert again.status_code == 404, again.text


def test_a_withdrawn_routine_cannot_be_completed(client, assigned):
    trainer, routine = assigned
    member = _login(client, "jisu@oncare.com")
    client.delete(
        f"/v1/trainer/clients/{MEMBER_ID}/routines/{routine['id']}",
        headers=_h(trainer),
    )

    res = client.post(
        f"/v1/me/coach/routines/{routine['id']}/complete",
        headers=_h(member),
        json={"minutes": 20, "intensity": "moderate"},
    )

    assert res.status_code == 404, res.text


def test_uncompleting_only_touches_today(client, assigned, today, monkeypatch):
    _, routine = assigned
    member = _login(client, "jisu@oncare.com")
    _complete(client, member, routine["id"])

    _move_to(monkeypatch, today + timedelta(days=1))
    _complete(client, member, routine["id"])
    undone = client.delete(
        f"/v1/me/coach/routines/{routine['id']}/complete", headers=_h(member)
    )
    assert undone.status_code == 200, undone.text
    assert undone.json()["completed"] is False

    # 어제 한 운동은 남는다 — 지난 날짜는 읽기 전용이다.
    rows = _completions(routine["id"])
    assert len(rows) == 1
    assert _mine(client, member, today.date())[routine["id"]]["completed"] is True


def test_withdrawing_a_pending_suggestion_removes_the_row(client):
    """승인 전 후보는 회원 목록에 걸린 적이 없다 — 남길 날이 없으니 행째 지운다."""
    trainer = _login(client, "trainer@oncare.com")
    created = client.post(
        f"/v1/trainer/clients/{MEMBER_ID}/routine-suggestions",
        headers=_h(trainer),
        json={"name": f"후보 {uuid4().hex[:6]}", "minutes": 8, "type": "스트레칭"},
    )
    assert created.status_code == 201, created.text
    suggestion_id = created.json()["id"]

    removed = client.delete(
        f"/v1/trainer/clients/{MEMBER_ID}/routines/{suggestion_id}",
        headers=_h(trainer),
    )

    assert removed.status_code == 200, removed.text
    db = SessionLocal()
    try:
        assert db.get(TrainerRoutine, suggestion_id) is None
    finally:
        db.close()


# ─────────────────────────────── 담당 없는 회원의 하루치 AI 추천 ───────────


@pytest.fixture()
def lone_member():
    """담당 트레이너 링크를 잠시 끊는다. 끝나면 되돌리고 자동 추천을 치운다."""
    db = SessionLocal()
    links = list(
        db.scalars(
            select(TrainerClient).where(TrainerClient.member_id == MEMBER_ID)
        ).all()
    )
    saved = {link.id: link.active for link in links}
    for link in links:
        link.active = False
    db.commit()
    db.close()

    yield MEMBER_ID

    db = SessionLocal()
    for link in db.scalars(
        select(TrainerClient).where(TrainerClient.member_id == MEMBER_ID)
    ).all():
        if link.id in saved:
            link.active = saved[link.id]
    autos = list(
        db.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.member_id == MEMBER_ID,
                TrainerRoutine.trainer_id.is_(None),
            )
        ).all()
    )
    for row in db.scalars(
        select(ExerciseSession).where(
            ExerciseSession.assigned_routine_id.in_([r.id for r in autos])
        )
    ).all():
        db.delete(row)
    for row in autos:
        db.delete(row)
    for convo in db.scalars(
        select(AiConversation).where(AiConversation.user_id == MEMBER_ID)
    ).all():
        db.delete(convo)
    db.commit()
    db.close()


def test_a_days_ai_recommendations_stay_on_that_day(
    client, lone_member, today, monkeypatch
):
    member = _login(client, "jisu@oncare.com")
    _move_to(monkeypatch, today)
    first_day = _mine(client, member)
    assert first_day

    _move_to(monkeypatch, today + timedelta(days=1))
    second_day = _mine(client, member)

    # 하루치 추천이라 다음 날은 그날 추천으로 바뀌고, 어제 것은 섞이지 않는다.
    assert second_day
    assert not set(first_day) & set(second_day)
    # 어제를 열면 어제 목록 그대로다.
    assert set(_mine(client, member, today.date())) == set(first_day)


def test_a_removed_ai_recommendation_does_not_come_back_the_same_day(
    client, lone_member, today, monkeypatch
):
    member = _login(client, "jisu@oncare.com")
    _move_to(monkeypatch, today)
    listed = _mine(client, member)
    removed_id, removed = next(iter(listed.items()))

    res = client.delete(
        f"/v1/me/coach/routines/{removed_id}", headers=_h(member)
    )
    assert res.status_code == 204, res.text

    again = _mine(client, member)
    assert removed_id not in again
    assert removed["name"] not in {row["name"] for row in again.values()}
