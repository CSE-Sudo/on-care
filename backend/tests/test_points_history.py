"""포인트 내역 — 날짜 단위 페이지와 AI 코치 대화 하루 묶음. (#2146) DB 필요(로컬 skip, CI 실행)."""
from __future__ import annotations

from datetime import date, timedelta
from uuid import uuid4

from app.models.models import PointsLedger


def _member(client) -> tuple[str, dict[str, str]]:
    email = f"hist-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    return client.get("/v1/users/me", headers=headers).json()["id"], headers


def _row(user_id: str, day: str, kind: str, reason: str, delta: int) -> PointsLedger:
    return PointsLedger(
        id=f"pl-{uuid4().hex[:12]}",
        user_id=user_id,
        kind=kind,
        delta=delta,
        reason=reason,
        source_type=reason,
        source_id=uuid4().hex,
        kst_date=day,
    )


def test_history_groups_ai_chat_per_day_and_pages_by_date(client, db_session):
    user_id, h = _member(client)
    start = date(2026, 9, 1)
    days = [(start + timedelta(days=i)).isoformat() for i in range(15)]
    db_session.add_all([_row(user_id, d, "earn", "diet_entry", 50) for d in days])
    last = days[-1]
    db_session.add_all(
        [_row(user_id, last, "spend", "ai_chat", -50) for _ in range(3)]
    )
    db_session.commit()

    first = client.get("/v1/me/points/history", headers=h).json()
    chat = [i for i in first["items"] if i["reason"] == "ai_chat"]
    # 대화 세 통이 하루 한 줄이다.
    assert [(c["count"], c["delta"]) for c in chat] == [(3, -150)]
    assert len({i["kst_date"] for i in first["items"]}) == 14
    assert first["next_before"] == days[1]

    rest = client.get(
        "/v1/me/points/history", params={"before": first["next_before"]}, headers=h
    ).json()
    assert [i["kst_date"] for i in rest["items"]] == [days[0]]
    assert rest["next_before"] is None
