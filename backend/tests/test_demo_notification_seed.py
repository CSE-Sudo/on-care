"""데모 회원 알림 시드 — 회원앱 데모 알림과 같은 목록인지. (#1812) DB 불필요."""
from __future__ import annotations

from datetime import timedelta

from app.api.v1.notifications import _action_for
from app.db.seed_notifications import DEMO_NOTIFICATIONS, LEGACY_DEMO_NOTIFICATION_IDS
from app.services import notification_service


def test_seed_has_ten_unique_notifications_newest_first():
    ids = [n.id for n in DEMO_NOTIFICATIONS]
    assert len(ids) == 10
    assert len(set(ids)) == len(ids)
    ages = [n.ago for n in DEMO_NOTIFICATIONS]
    assert ages == sorted(ages), "최신순이어야 목록 순서와 time_ago 가 맞는다"
    assert all(age > timedelta(0) for age in ages)


def test_seed_drops_the_previous_target_wording():
    text = " ".join(f"{n.title} {n.body}" for n in DEMO_NOTIFICATIONS)
    for word in ("혈압", "당뇨", "검진"):
        assert word not in text
    assert not set(LEGACY_DEMO_NOTIFICATION_IDS) & {n.id for n in DEMO_NOTIFICATIONS}


def test_unread_alerts_sit_on_top():
    reads = [n.read for n in DEMO_NOTIFICATIONS]
    assert reads.count(False) == 6
    first_read = reads.index(True)
    assert all(reads[first_read:]), "읽은 알림 뒤에 안 읽은 알림이 끼지 않는다"


def _target(title: str) -> str | None:
    item = next(n for n in DEMO_NOTIFICATIONS if n.title == title)
    action = _action_for(item.category)
    return None if action is None else action.target


def test_each_alert_opens_the_same_screen_as_the_app_demo():
    assert _target("새 운동 루틴이 도착했어요") == "exercise"
    assert _target("내일 PT 일정이 있어요") == "schedule"
    assert _target("이번 주 리포트가 등록됐어요") == "coach_chat"
    assert _target("트레이너 피드백 도착") == "coach_chat"
    # 공지는 갈 곳이 없다 — 앱 데모도 같은 알림에 목적지를 두지 않는다.
    assert _target("서비스 점검 안내") is None


def test_categories_are_known_backend_categories():
    known = {
        "reminder",
        "health_check",
        "achievement",
        "system",
        notification_service.MEMBER_COACH_CHAT,
        notification_service.MEMBER_ROUTINE,
        notification_service.MEMBER_SCHEDULE,
        notification_service.MEMBER_CONSULTATION,
    }
    assert {n.category for n in DEMO_NOTIFICATIONS} <= known
    assert all(len(n.category) <= 20 for n in DEMO_NOTIFICATIONS), "컬럼 길이 20"
