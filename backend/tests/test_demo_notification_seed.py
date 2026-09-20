"""데모 회원 알림 시드 — 회원앱 데모 알림과 같은 목록인지. (#1812) DB 불필요."""
from __future__ import annotations

from datetime import date, timedelta

from app.api.v1.notifications import _action_for
from app.db.demo_fixture import load_fixture
from app.db.seed_notifications import DEMO_NOTIFICATIONS, LEGACY_DEMO_NOTIFICATION_IDS
from app.services import notification_service


def test_seed_has_nine_unique_notifications_newest_first():
    ids = [n.id for n in DEMO_NOTIFICATIONS]
    assert len(ids) == 9
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
    assert reads.count(False) == 7
    first_read = reads.index(True)
    assert all(reads[first_read:]), "읽은 알림 뒤에 안 읽은 알림이 끼지 않는다"


def _target(title: str) -> str | None:
    item = next(n for n in DEMO_NOTIFICATIONS if n.title == title)
    action = _action_for(item.category)
    return None if action is None else action.target


def test_each_alert_opens_the_same_screen_as_the_app_demo():
    assert _target("새 운동 루틴이 도착했어요") == "exercise"
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


# ── 문구가 데모 픽스처(김민수)와 같은 사실을 말하는지 ──────────────────────
# 알림은 식단·운동·채팅 목업을 따라 적은 문장이라, 픽스처가 바뀌면 조용히 틀린
# 말을 하게 된다. 요일마다 달라지는 값(주간 운동 시간·리포트 주차)은 문구에 없다.


def _body(title: str) -> str:
    return next(n.body for n in DEMO_NOTIFICATIONS if n.title == title)


def test_sodium_alert_quotes_todays_fixture_total():
    today = load_fixture().days_for(date(2026, 9, 15))[-1]
    assert f"{today.sodium_mg:,}mg" in _body("나트륨 섭취 주의")


def test_dinner_reminder_is_for_a_day_without_dinner():
    today = load_fixture().days_for(date(2026, 9, 15))[-1]
    assert "dinner" not in {m.meal_type for m in today.meals}
    item = next(n for n in DEMO_NOTIFICATIONS if n.title == "저녁 식단을 기록해 주세요")
    assert not item.read and item.ago < timedelta(hours=1), "오늘 저녁 알림이다"


def test_routine_alert_names_a_routine_in_the_fixture():
    assert "걷기" in _body("새 운동 루틴이 도착했어요")
    assert any("걷기" in r.name for r in load_fixture().routines)


def test_streak_alert_matches_an_unbroken_meal_history():
    # 픽스처의 빈 날은 요일이 정해져 있어, 오늘이 무슨 요일이든 끊기지 않은 기간이
    # 보름을 넘는다. 일주일 치를 모두 돌려 본다.
    #
    # 예전에는 "한 달 넘게" 였다. 보호권(#1788)을 시연하려면 최근 30일 안에 빈 날이
    # 하나 있어야 하는데(#2075 기록 그래프에서 그 칸을 눌러 쓴다), 그러면 식단이
    # 끊기지 않은 기간이 한 달을 넘을 수 없다 — 두 문구가 같은 픽스처에서 동시에
    # 참일 수 없어 알림 쪽을 사실에 맞췄다.
    for offset in range(7):
        days = load_fixture().days_for(date(2026, 9, 14) + timedelta(days=offset))
        run = 0
        for day in reversed(days):
            if not day.meals:
                break
            run += 1
        assert run > 15, f"{days[-1].iso}: {run}일 — '보름 넘게' 가 틀린다"
    body = _body("식단 기록을 꾸준히 이어가고 있어요")
    assert "보름 넘게" in body
    assert not any(ch.isdigit() for ch in body)


def test_no_alert_hardcodes_a_date_dependent_label():
    text = " ".join(f"{n.title} {n.body}" for n in DEMO_NOTIFICATIONS)
    for word in ("주차", "내일 PT", "13회차", "80%"):
        assert word not in text
