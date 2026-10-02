"""실서버 데모 계정 알림이 회원 앱 데모와 같게 보이는지. (#2690·#2691) DB 필요.

회원 앱 데모 알림함이 기준이다 — 알림별 목적지(PT 완료 → 운동 등)와 언제 열어도
같은 시각("10분 전 … 어제")을 실서버 데모 계정도 따른다.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import update

from app.db.init_db import DEMO_USER_ID
from app.db.seed_notifications import DEMO_AGO_BY_ID, DEMO_NOTIFICATIONS, seed_demo_notifications
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
        "exercise",  # 새 운동 루틴
        "coach_chat",  # 주간 리포트
        "exercise",  # PT 수업 완료
        "coach_chat",  # 트레이너 피드백
        "exercise",  # 운동 목표
        "dashboard",  # 식단 연속 기록
        None,  # 점검 공지
    ]


def test_demo_alerts_keep_their_times_and_move_to_today(client, db_session):
    # 사흘이 지난 것처럼 밀어 둔다.
    db_session.execute(
        update(Notification)
        .where(Notification.id.in_(DEMO_IDS))
        .values(created_at=Notification.created_at - timedelta(days=3))
    )
    db_session.commit()

    inbox = _inbox(client)
    assert [inbox[n]["time_ago"] for n in DEMO_IDS] == [
        "30분 전",
        "45분 전",
        "1시간 전",
        "2시간 전",
        "3시간 전",
        "어제",
        "어제",
    ]
    en = _inbox(client, {"Accept-Language": "en"})
    assert en["noti-demo-3"]["time_ago"] == "30 min ago"
    assert en["noti-demo-8"]["time_ago"] == "yesterday"

    # 목록을 읽을 때 오늘로 옮겨졌다 — 새로 생긴 알림과의 순서도 맞는다.
    db_session.expire_all()
    now = datetime.now(timezone.utc)
    for nid in DEMO_IDS:
        row = db_session.get(Notification, nid)
        created = row.created_at
        if created.tzinfo is None:
            created = created.replace(tzinfo=timezone.utc)
        drift = (now - created) - DEMO_AGO_BY_ID[nid]
        assert abs(drift) < timedelta(minutes=5), nid


def test_seed_backfills_targets_for_rows_seeded_before_the_column(db_session):
    db_session.execute(
        update(Notification)
        .where(Notification.id.in_(DEMO_IDS))
        .values(action_target=None)
    )
    db_session.commit()

    assert seed_demo_notifications(db_session, DEMO_USER_ID) == 0

    db_session.expire_all()
    assert db_session.get(Notification, "noti-demo-5").action_target == "exercise"
    assert db_session.get(Notification, "noti-demo-7").action_target == "exercise"
    assert db_session.get(Notification, "noti-demo-9").action_target is None


def test_removed_diet_alerts_leave_the_demo_inbox(client, db_session):
    # 예전 시드가 남긴 식단 알림 두 건은 다시 시드할 때 걷힌다(#2854).
    for nid, title in (
        ("noti-demo-1", "나트륨 섭취 주의"),
        ("noti-demo-2", "저녁 식단을 기록해 주세요"),
    ):
        if db_session.get(Notification, nid) is None:
            db_session.add(
                Notification(
                    id=nid,
                    user_id=DEMO_USER_ID,
                    title=title,
                    body="",
                    category="reminder",
                    read=False,
                    created_at=datetime.now(timezone.utc),
                )
            )
    db_session.commit()

    assert seed_demo_notifications(db_session, DEMO_USER_ID) == 0

    db_session.expire_all()
    assert db_session.get(Notification, "noti-demo-1") is None
    assert db_session.get(Notification, "noti-demo-2") is None
    inbox = _inbox(client)
    assert "noti-demo-1" not in inbox
    assert "noti-demo-2" not in inbox
