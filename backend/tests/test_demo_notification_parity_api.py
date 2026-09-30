"""실서버 데모 계정 알림이 회원 앱 데모와 같게 보이는지. (#2690) DB 필요.

회원 앱 데모 알림함이 기준이다 — 알림별 목적지(나트륨 → 식단 등)를 실서버 데모
계정도 따른다.
"""
from __future__ import annotations

from sqlalchemy import update

from app.db.init_db import DEMO_USER_ID
from app.db.seed_notifications import DEMO_NOTIFICATIONS, seed_demo_notifications
from app.models.models import Notification

DEMO_IDS = [n.id for n in DEMO_NOTIFICATIONS]


def _token(client) -> str:
    res = client.post(
        "/v1/auth/login",
        data={"username": "minsu@oncare.com", "password": "oncare123"},
    )
    assert res.status_code == 200, res.text
    return res.json()["access_token"]


def _inbox(client, headers: dict[str, str] | None = None) -> dict[str, dict]:
    res = client.get(
        "/v1/notifications",
        params={"limit": 100},
        headers={"Authorization": f"Bearer {_token(client)}", **(headers or {})},
    )
    assert res.status_code == 200, res.text
    return {row["id"]: row for row in res.json()}


def test_demo_alerts_open_the_same_screens_as_the_app_demo(client, db_session):
    inbox = _inbox(client)

    def target(nid: str) -> str | None:
        action = inbox[nid]["action"]
        return None if action is None else action["target"]

    assert [target(n) for n in DEMO_IDS] == [
        "diet",  # 나트륨 섭취 주의
        "diet",  # 저녁 식단 기록
        "exercise",  # 새 운동 루틴
        "coach_chat",  # 주간 리포트
        "exercise",  # PT 수업 완료
        "coach_chat",  # 트레이너 피드백
        "exercise",  # 운동 목표
        "dashboard",  # 식단 연속 기록
        None,  # 점검 공지
    ]


def test_seed_backfills_targets_for_rows_seeded_before_the_column(db_session):
    db_session.execute(
        update(Notification)
        .where(Notification.id.in_(DEMO_IDS))
        .values(action_target=None)
    )
    db_session.commit()

    assert seed_demo_notifications(db_session, DEMO_USER_ID) == 0

    db_session.expire_all()
    assert db_session.get(Notification, "noti-demo-1").action_target == "diet"
    assert db_session.get(Notification, "noti-demo-7").action_target == "exercise"
    assert db_session.get(Notification, "noti-demo-9").action_target is None
