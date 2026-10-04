"""조회 시점에 만드는 경로의 동시 요청. (#3092) DB 필요.

"읽을 때 없으면 만든다" 경로 세 곳이 확인과 생성 사이에 잠금도 유일 제약도
없어, 같은 회원의 요청 두 개가 겹치면 행이 두 벌 생기거나 늦은 쪽이 500 이었다.

- 담당 없는 회원의 오늘 AI 추천 개인운동 — 운동 탭이 두 API 를 함께 읽는다.
- 식단 4주 추천 메뉴 리스트 — AI 를 기다리는 동안 두 번째 조회가 들어온다.
- 회원 알림 설정 첫 저장 — 앱이 토글마다 따로 저장한다.

두 스레드를 `Barrier` 로 맞춰 같은 순간에 들여보낸다
(`test_trainer_routine_idempotency.py` 와 같은 방식).
"""
from __future__ import annotations

import json
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from threading import Barrier, Lock

import pytest
from sqlalchemy import delete, func, select

from app.core import clock
from app.core.security import hash_password
from app.data import diet_menu_catalog as catalog
from app.db.session import SessionLocal
from app.models.models import (
    DietMenuPlan,
    HealthProfile,
    MemberNotificationSetting,
    TrainerRoutine,
    User,
)
from app.services import auto_routine_service
from app.services import diet_menu_plan as menu_plan

PASSWORD = "test-pw-1234"


def _together(*calls):
    """[calls] 를 각자 스레드에서 같은 순간에 시작해 결과를 순서대로 돌려준다."""
    barrier = Barrier(len(calls))

    def run(call):
        barrier.wait()
        return call()

    with ThreadPoolExecutor(max_workers=len(calls)) as pool:
        futures = [pool.submit(run, call) for call in calls]
        return [f.result(timeout=30) for f in futures]


def _in_own_session(fn):
    """스레드마다 따로 세션을 연다 — 요청 둘이 각자 트랜잭션을 갖는 것과 같다."""

    def call():
        db = SessionLocal()
        try:
            return fn(db)
        finally:
            db.close()

    return call


@pytest.fixture()
def member(client):
    """담당 트레이너가 없고 알림 설정·추천 행도 없는 새 회원."""
    db = SessionLocal()
    user = User(
        id=f"user-lazy-{uuid.uuid4().hex[:12]}",
        email=f"lazy-{uuid.uuid4().hex[:8]}@example.com",
        name="동시 요청",
        hashed_password=hash_password(PASSWORD),
        role="member",
        is_active=True,
    )
    db.add(user)
    db.add(HealthProfile(user_id=user.id))
    db.commit()
    member_id, email = user.id, user.email
    db.close()

    yield member_id, email

    db = SessionLocal()
    db.execute(delete(TrainerRoutine).where(TrainerRoutine.member_id == member_id))
    db.execute(delete(DietMenuPlan).where(DietMenuPlan.user_id == member_id))
    db.execute(
        delete(MemberNotificationSetting).where(
            MemberNotificationSetting.member_id == member_id
        )
    )
    db.execute(delete(HealthProfile).where(HealthProfile.user_id == member_id))
    db.execute(delete(User).where(User.id == member_id))
    db.commit()
    db.close()


def _token(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ── 담당 없는 회원의 오늘 AI 추천 ───────────────────────────────────────


def _auto_rows(member_id: str) -> list[tuple[str, int]]:
    db = SessionLocal()
    try:
        return sorted(
            db.execute(
                select(TrainerRoutine.name, TrainerRoutine.minutes).where(
                    TrainerRoutine.member_id == member_id,
                    TrainerRoutine.trainer_id.is_(None),
                    TrainerRoutine.client_request_id
                    == f"auto-{clock.now().date().isoformat()}",
                )
            ).all()
        )
    finally:
        db.close()


def test_concurrent_auto_routines_are_made_once(member):
    member_id, _ = member
    ensure = _in_own_session(
        lambda db: auto_routine_service.ensure_auto_routines(db, member_id)
    )

    _together(ensure, ensure)

    expected = sorted((name, minutes) for name, minutes, *_ in auto_routine_service.SAFE_ROUTINES)
    assert _auto_rows(member_id) == expected, "같은 추천이 두 벌 생겼다"


def test_concurrent_remake_after_discomfort_stays_single(member, monkeypatch):
    """불편이 바뀌어 다시 만들 때도 두 요청이 함께 지우고 함께 넣지 않는다."""
    member_id, _ = member
    _in_own_session(
        lambda db: auto_routine_service.ensure_auto_routines(db, member_id)
    )()

    # 대화에서 "운동이 힘들다" 를 찾은 것처럼 — 시간을 줄여 다시 만들게 된다.
    struggled = [
        type("Insight", (), {"kind": auto_routine_service.insights.KIND_NEGATIVE, "body_part": None})()
    ]
    monkeypatch.setattr(
        auto_routine_service.insights, "recent_insights", lambda db, member_id: struggled
    )
    ensure = _in_own_session(
        lambda db: auto_routine_service.ensure_auto_routines(db, member_id)
    )

    _together(ensure, ensure)

    rows = _auto_rows(member_id)
    assert len(rows) == len(auto_routine_service.SAFE_ROUTINES), rows
    assert all(
        minutes == max(auto_routine_service._MIN_MINUTES, full // 2)
        for (_, minutes), (_, full, *_) in zip(
            rows, sorted(auto_routine_service.SAFE_ROUTINES), strict=True
        )
    )


def test_routines_and_advice_read_together_show_one_set(client, member):
    """운동 탭이 개인운동과 기간 조언을 함께 읽어도 목록이 한 벌이다."""
    member_id, email = member
    token = _token(client, email)

    routines, advice = _together(
        lambda: client.get("/v1/me/coach/routines", headers=_h(token)),
        lambda: client.get("/v1/exercise/advice", headers=_h(token)),
    )

    assert routines.status_code == 200, routines.text
    assert advice.status_code == 200, advice.text
    assert len(_auto_rows(member_id)) == len(auto_routine_service.SAFE_ROUTINES)
    listed = client.get("/v1/me/coach/routines", headers=_h(token)).json()
    names = [r["name"] for r in listed]
    assert len(names) == len(set(names)), names


# ── 식단 4주 추천 메뉴 리스트 ───────────────────────────────────────────


def _llm_payload(prefix: str) -> str:
    items = [
        {
            "slot": slot, "name": f"{prefix}{slot[:2]}{i}", "tag": "protein_high",
            "keyword": "고단백", "kcal": 400, "protein_g": 30, "sodium_mg": 500,
        }
        for slot, n in catalog.SLOT_COUNTS.items()
        for i in range(n)
    ]
    return json.dumps({"items": items}, ensure_ascii=False)


class _SlowLLM:
    """부를 때마다 잠깐 기다린다 — 그 사이 두 번째 조회가 들어오게 한다."""

    def __init__(self) -> None:
        self.calls = 0
        self._lock = Lock()

    def __call__(self, system: str, user: str) -> str:
        with self._lock:
            self.calls += 1
            n = self.calls
        time.sleep(0.5)
        return _llm_payload(f"메뉴{n}-")


def _now() -> datetime:
    return datetime(2026, 9, 21, 12, 0, tzinfo=clock.SEOUL)


def _plan_count(member_id: str) -> int:
    db = SessionLocal()
    try:
        return db.scalar(
            select(func.count()).select_from(DietMenuPlan).where(DietMenuPlan.user_id == member_id)
        )
    finally:
        db.close()


def test_concurrent_first_plan_calls_ai_once(member, monkeypatch):
    member_id, _ = member
    fake = _SlowLLM()
    monkeypatch.setattr(menu_plan, "_call_llm", fake)
    get = _in_own_session(lambda db: menu_plan.get_plan(db, member_id, now=_now()))

    first, second = _together(get, get)

    assert fake.calls == 1
    assert first.id == second.id
    assert first.items == second.items
    assert _plan_count(member_id) == 1


def test_concurrent_remake_keeps_previous_and_one_new(member, monkeypatch):
    """만료로 다시 만들 때도 AI 한 번, 남는 행은 직전 + 새 것 둘이다."""
    member_id, _ = member
    fake = _SlowLLM()
    monkeypatch.setattr(menu_plan, "_call_llm", fake)
    old = _in_own_session(lambda db: menu_plan.get_plan(db, member_id, now=_now()))()
    later = _now() + timedelta(days=menu_plan.PLAN_DAYS)
    get = _in_own_session(lambda db: menu_plan.get_plan(db, member_id, now=later))

    first, second = _together(get, get)

    assert fake.calls == 2  # 처음 1번 + 다시 만들기 1번
    assert first.id == second.id != old.id
    assert _plan_count(member_id) == 2


def test_concurrent_retry_fills_once(member, monkeypatch):
    """AI 실패로 카탈로그를 채운 리스트의 재시도도 한 번만 AI 를 부른다."""
    member_id, _ = member

    def fail(system: str, user: str) -> str:
        raise RuntimeError("키 없음")

    monkeypatch.setattr(menu_plan, "_call_llm", fail)
    rules = _in_own_session(lambda db: menu_plan.get_plan(db, member_id, now=_now()))()
    assert rules.source == "rules"

    fake = _SlowLLM()
    monkeypatch.setattr(menu_plan, "_call_llm", fake)
    later = _now() + menu_plan.RETRY_AFTER + timedelta(minutes=1)
    get = _in_own_session(lambda db: menu_plan.get_plan(db, member_id, now=later))

    first, second = _together(get, get)

    assert fake.calls == 1
    assert first.id == second.id == rules.id
    assert first.source == second.source == "llm"
    assert first.items == second.items
    assert _plan_count(member_id) == 1


# ── 회원 알림 설정 첫 저장 ──────────────────────────────────────────────


def test_concurrent_first_settings_save_keeps_both(client, member):
    _, email = member
    token = _token(client, email)

    def put(body):
        return lambda: client.put(
            "/v1/users/me/notification-settings", json=body, headers=_h(token)
        )

    a, b = _together(put({"weekly_report": True}), put({"diet_log": False}))

    assert [a.status_code, b.status_code] == [200, 200], [a.text, b.text]
    final = client.get("/v1/users/me/notification-settings", headers=_h(token)).json()
    assert final["weekly_report"] is True
    assert final["diet_log"] is False
    # 보내지 않은 칸은 기본값 그대로다.
    assert final["exercise_reminder"] is True


def test_settings_save_keeps_existing_behaviour(client, member):
    """빈 요청은 행을 만들지 않고, 같은 키를 다시 저장하면 마지막 값이 남는다."""
    member_id, email = member
    token = _token(client, email)

    empty = client.put("/v1/users/me/notification-settings", json={}, headers=_h(token))
    assert empty.status_code == 200, empty.text
    db = SessionLocal()
    try:
        assert db.get(MemberNotificationSetting, member_id) is None
    finally:
        db.close()

    for value in (False, True, False):
        saved = client.put(
            "/v1/users/me/notification-settings",
            json={"trainer_message": value},
            headers=_h(token),
        )
        assert saved.status_code == 200, saved.text
        assert saved.json()["trainer_message"] is value
