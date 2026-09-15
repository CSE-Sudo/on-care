"""활동 포인트 적립·하루 한도·중복 방지·삭제 회수. (#1786) DB 필요(로컬 skip, CI 실행).

기록 규칙은 적립 안내창과 같다 — 식단 +50P(하루 3회), 운동 직접 추가 +20P(하루
3회), 추천·배정 운동 완료 +50P(하루 1회, AI 추천과 트레이너 배정이 한도를 함께 쓴다). 새로 가입한 회원으로 확인해 다른 테스트가
만든 적립과 섞이지 않게 한다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest
from sqlalchemy import delete, select

_JPEG = b"\xff\xd8\xff\xe0\x00\x10JFIF fake-image-bytes"


def _register(client) -> dict[str, str]:
    email = f"pts-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _balance(client, headers) -> int:
    r = client.get("/v1/users/me/health", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()["activity_points"]


def _analyze(client, headers, key: str | None = None) -> dict:
    data = {"meal_type": "lunch"}
    if key is not None:
        data["idempotency_key"] = key
    r = client.post(
        "/v1/diet/analyze",
        files={"image": ("food.jpg", _JPEG, "image/jpeg")},
        data=data,
        headers=headers,
    )
    assert r.status_code == 200, r.text
    return r.json()


def _add_exercise(client, headers) -> dict:
    r = client.post(
        "/v1/exercise/sessions",
        json={"type": "cardio", "name": "걷기", "minutes": 20, "calories": 0},
        headers=headers,
    )
    assert r.status_code == 201, r.text
    return r.json()


def _complete(client, headers, routine_id: str) -> dict:
    r = client.post(
        f"/v1/me/coach/routines/{routine_id}/complete",
        json={"minutes": 10, "intensity": "moderate", "member_note": ""},
        headers=headers,
    )
    assert r.status_code == 200, r.text
    return r.json()


def test_new_member_starts_at_zero(client):
    h = _register(client)
    assert _balance(client, h) == 0


def test_diet_entry_awards_50_up_to_three_times_a_day(client):
    h = _register(client)

    awarded = [_analyze(client, h)["points"]["awarded"] for _ in range(4)]

    assert awarded == [50, 50, 50, 0]
    assert _balance(client, h) == 150


def test_points_object_shape_on_create_responses(client):
    h = _register(client)

    diet = _analyze(client, h)
    exercise = _add_exercise(client, h)

    assert diet["points"] == {"awarded": 50, "balance": 50}
    assert exercise["points"] == {"awarded": 20, "balance": 70}
    # 목록에는 붙지 않는다 — 적립은 새로 추가한 순간의 일이다.
    week = client.get("/v1/exercise/weeks/current", headers=h).json()
    assert week["sessions"]
    assert all("points" not in s for s in week["sessions"])


def test_exercise_manual_awards_20_up_to_three_times_a_day(client):
    h = _register(client)

    awarded = [_add_exercise(client, h)["points"]["awarded"] for _ in range(4)]

    assert awarded == [20, 20, 20, 0]
    assert _balance(client, h) == 60


def test_diet_and_exercise_caps_are_counted_separately(client):
    h = _register(client)
    for _ in range(3):
        _analyze(client, h)

    assert _add_exercise(client, h)["points"]["awarded"] == 20
    assert _balance(client, h) == 170


def test_retry_with_same_idempotency_key_is_not_awarded_twice(client):
    h = _register(client)
    key = f"pts-{uuid4().hex}"

    first = _analyze(client, h, key)
    retried = _analyze(client, h, key)

    assert retried["entry_id"] == first["entry_id"]
    # 재시도는 처음 응답과 같은 값을 싣고, 잔액은 그대로다.
    assert retried["points"] == {"awarded": 50, "balance": 50}
    assert _balance(client, h) == 50


def test_deleting_diet_entry_revokes_award_and_frees_the_daily_slot(client):
    h = _register(client)
    ids = [_analyze(client, h)["entry_id"] for _ in range(3)]

    r = client.delete(f"/v1/diet/entries/{ids[0]}", headers=h)
    assert r.status_code == 200, r.text
    assert _balance(client, h) == 100

    # 지운 기록의 몫이 한도에서 빠진다 — 다시 올린 끼니는 새 기록이다.
    assert _analyze(client, h)["points"] == {"awarded": 50, "balance": 150}
    assert _analyze(client, h)["points"]["awarded"] == 0


def test_deleting_an_unawarded_entry_revokes_nothing(client):
    h = _register(client)
    for _ in range(3):
        _analyze(client, h)
    capped = _analyze(client, h)
    assert capped["points"]["awarded"] == 0

    client.delete(f"/v1/diet/entries/{capped['entry_id']}", headers=h)

    assert _balance(client, h) == 150


def test_deleting_exercise_session_revokes_award(client):
    h = _register(client)
    session = _add_exercise(client, h)

    r = client.delete(f"/v1/exercise/sessions/{session['id']}", headers=h)
    assert r.status_code == 200, r.text

    assert _balance(client, h) == 0


def test_updating_a_record_does_not_award_again(client):
    h = _register(client)
    session = _add_exercise(client, h)

    r = client.put(
        f"/v1/exercise/sessions/{session['id']}",
        json={"type": "cardio", "name": "걷기", "minutes": 40, "calories": 0},
        headers=h,
    )
    assert r.status_code == 200, r.text
    assert "points" not in r.json()
    assert _balance(client, h) == 20


def test_daily_cap_resets_on_the_next_kst_day(client, monkeypatch):
    from app.core import clock

    h = _register(client)
    monkeypatch.setattr(clock, "today_iso", lambda: "2001-01-01")
    for _ in range(3):
        _add_exercise(client, h)
    assert _add_exercise(client, h)["points"]["awarded"] == 0

    monkeypatch.setattr(clock, "today_iso", lambda: "2001-01-02")
    assert _add_exercise(client, h)["points"]["awarded"] == 20


def test_ai_routine_completion_awards_50_once_a_day_and_undo_revokes(client):
    # 담당 트레이너가 없는 회원은 AI 가 직접 추천한 루틴을 받는다(#782).
    h = _register(client)
    routines = client.get("/v1/me/coach/routines", headers=h).json()
    ai = [r for r in routines if r["source"] == "ai"]
    assert len(ai) >= 2

    first = _complete(client, h, ai[0]["id"])
    assert first["completed"] is True
    assert first["points"] == {"awarded": 50, "balance": 50}
    # 하루 1회 — 두 번째 추천은 저장되지만 적립은 없다.
    assert _complete(client, h, ai[1]["id"])["points"]["awarded"] == 0
    # 재전송은 새로 적립하지 않고 처음 받은 값을 돌려준다.
    assert _complete(client, h, ai[0]["id"])["points"] == {
        "awarded": 50,
        "balance": 50,
    }

    undone = client.delete(
        f"/v1/me/coach/routines/{ai[0]['id']}/complete", headers=h
    )
    assert undone.status_code == 200, undone.text
    assert _balance(client, h) == 0

    # 되돌린 완료의 몫은 한도에서 빠져, 다시 완료하면 새 기록으로 적립된다.
    assert _complete(client, h, ai[0]["id"])["points"]["awarded"] == 50
    assert _balance(client, h) == 50


def test_trainer_assigned_routine_completion_awards_and_shares_cap_with_ai(
    client, db_session
):
    from app.models.models import TrainerRoutine

    h = _register(client)
    member_id = client.get("/v1/users/me", headers=h).json()["id"]
    routine_id = f"pts-rt-{uuid4().hex[:8]}"
    db_session.add(
        TrainerRoutine(
            id=routine_id,
            trainer_id=None,
            member_id=member_id,
            name="트레이너 배정",
            minutes=20,
            type="유산소",
            reason="테스트",
            source="trainer",
            status="approved",
        )
    )
    db_session.commit()
    ai = [
        r
        for r in client.get("/v1/me/coach/routines", headers=h).json()
        if r["source"] == "ai"
    ]
    assert ai

    # 트레이너 배정 루틴 완료도 +50P 다.
    done = _complete(client, h, routine_id)
    assert done["completed"] is True
    assert done["points"] == {"awarded": 50, "balance": 50}
    # 재전송은 새로 적립하지 않는다.
    assert _complete(client, h, routine_id)["points"] == {
        "awarded": 50,
        "balance": 50,
    }

    # 하루 1회는 AI 추천과 함께 쓰는 한도다 — 같은 날 AI 루틴은 적립이 없다.
    assert _complete(client, h, ai[0]["id"])["points"] == {
        "awarded": 0,
        "balance": 50,
    }

    # 배정 완료를 되돌리면 회수되고 그날 한도가 풀린다.
    undone = client.delete(
        f"/v1/me/coach/routines/{routine_id}/complete", headers=h
    )
    assert undone.status_code == 200, undone.text
    assert _balance(client, h) == 0
    client.delete(f"/v1/me/coach/routines/{ai[0]['id']}/complete", headers=h)
    assert _complete(client, h, ai[0]["id"])["points"] == {
        "awarded": 50,
        "balance": 50,
    }


def test_revoke_never_takes_the_balance_below_zero(client, db_session):
    from app.models.models import HealthProfile, PointsLedger

    h = _register(client)
    member_id = client.get("/v1/users/me", headers=h).json()["id"]
    entry_id = _analyze(client, h)["entry_id"]
    # 그사이 포인트를 써서 잔액이 10 만 남았다고 둔다.
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    profile.activity_points = 10
    db_session.commit()

    client.delete(f"/v1/diet/entries/{entry_id}", headers=h)

    assert _balance(client, h) == 0
    db_session.expire_all()
    revoke = db_session.scalar(
        select(PointsLedger).where(
            PointsLedger.user_id == member_id, PointsLedger.kind == "revoke"
        )
    )
    # 내역에는 실제로 뺀 값이 남는다.
    assert revoke is not None
    assert revoke.delta == -10


def test_same_source_cannot_be_awarded_twice(client, db_session):
    from app.services import points_service

    h = _register(client)
    member_id = client.get("/v1/users/me", headers=h).json()["id"]
    entry_id = _analyze(client, h)["entry_id"]

    again = points_service.award(
        db_session, member_id, points_service.DIET_ENTRY, entry_id
    )
    db_session.commit()

    assert again.awarded == 50  # 처음 받은 값을 돌려줄 뿐 새로 쌓지 않는다
    assert again.balance == 50
    assert _balance(client, h) == 50


@pytest.fixture()
def sungho_profile(db_session):
    """데모 회원 박성호의 잔액을 잠시 바꿨다가 되돌린다."""
    from app.models.models import HealthProfile, PointsLedger

    member_id = "user-sungho"
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    if profile is None:
        pytest.skip("박성호 시드 프로필이 없다")
    saved = profile.activity_points
    yield member_id
    db_session.rollback()
    db_session.execute(
        delete(PointsLedger).where(
            PointsLedger.user_id == member_id,
            PointsLedger.source_id == "seed-test",
        )
    )
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    profile.activity_points = saved
    db_session.commit()


def test_demo_members_start_with_the_opening_balance(db_session, sungho_profile):
    from app.db.seed_member_data import seed_demo_opening_points
    from app.models.models import HealthProfile, PointsLedger
    from app.services import points_service

    def points() -> int:
        db_session.expire_all()
        return db_session.scalar(
            select(HealthProfile.activity_points).where(
                HealthProfile.user_id == sungho_profile
            )
        )

    db_session.execute(
        HealthProfile.__table__.update()
        .where(HealthProfile.user_id == sungho_profile)
        .values(activity_points=0)
    )
    db_session.commit()
    seed_demo_opening_points()
    assert points() == points_service.DEMO_OPENING_POINTS

    # 적립·회수를 한 번이라도 거친 잔액은 회원이 만든 값이라 되돌리지 않는다.
    db_session.add(
        PointsLedger(
            id=f"pts-{uuid4().hex[:12]}",
            user_id=sungho_profile,
            kind="revoke",
            delta=0,
            reason="diet_entry",
            source_type="diet_entry",
            source_id="seed-test",
            kst_date="2001-01-01",
        )
    )
    db_session.execute(
        HealthProfile.__table__.update()
        .where(HealthProfile.user_id == sungho_profile)
        .values(activity_points=0)
    )
    db_session.commit()
    seed_demo_opening_points()
    assert points() == 0
