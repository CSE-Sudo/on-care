"""데모 회원 알림 시드 — 회원앱 데모 알림과 같은 목록인지. (#1812) DB 불필요."""
from __future__ import annotations

from datetime import date, timedelta

from app.api.v1.notifications import _action_for
from app.db.demo_fixture import load_fixture
from app.db.seed_notifications import (
    DEMO_NOTIFICATIONS,
    LEGACY_DEMO_NOTIFICATION_IDS,
    demo_time_ago,
)
from app.services import notification_service


def test_seed_has_seven_unique_notifications_newest_first():
    ids = [n.id for n in DEMO_NOTIFICATIONS]
    assert len(ids) == 7
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
    assert reads.count(False) == 5
    first_read = reads.index(True)
    assert all(reads[first_read:]), "읽은 알림 뒤에 안 읽은 알림이 끼지 않는다"


def _target(title: str) -> str | None:
    item = next(n for n in DEMO_NOTIFICATIONS if n.title == title)
    action = _action_for(item.category, "ko", item.target)
    return None if action is None else action.target


def test_each_alert_opens_the_same_screen_as_the_app_demo():
    # 회원 앱 데모 목록(`demo_alert_keys.dart` 의 `kDemoAlertActionBySeedId`)과 같다.
    # 리마인더라도 운동 목표는 운동이다(#2690).
    assert _target("새 개인운동이 왔어요") == "exercise"
    assert _target("주간 리포트가 도착했어요") == "coach_chat"
    assert _target("12회차 PT를 마쳤어요") == "exercise"
    assert _target("트레이너 피드백이 도착했어요") == "coach_chat"
    assert _target("이번 주 운동 목표까지 조금 남았어요") == "exercise"
    assert _target("식단 기록을 꾸준히 이어가고 있어요") == "dashboard"
    # 공지는 갈 곳이 없다 — 앱 데모도 같은 알림에 목적지를 두지 않는다.
    assert _target("서비스 점검이 예정돼 있어요") is None


def test_alert_specific_target_keeps_the_category_label_when_it_matches():
    # 갈래별 표와 목적지가 같으면 그 라벨이다. 다르면 목적지 라벨이다(#2690).
    assert _action_for("routine", "ko", "exercise").label == "운동 보기"
    assert _action_for("reminder", "ko", "diet").label == "식단 보기"
    assert _action_for("reminder", "en", "diet").label == "View diet"
    assert _action_for("system", "ko", None) is None


def test_demo_alerts_show_the_same_times_as_the_app_demo():
    # 회원 앱 데모와 같은 문구 — 하루 지난 알림은 "어제" 다(#2691).
    assert [demo_time_ago(n.ago, "ko") for n in DEMO_NOTIFICATIONS] == [
        "30분 전",
        "45분 전",
        "1시간 전",
        "2시간 전",
        "3시간 전",
        "어제",
        "어제",
    ]
    assert demo_time_ago(timedelta(minutes=10), "en") == "10 min ago"
    assert demo_time_ago(timedelta(hours=1), "en") == "1 hour ago"
    assert demo_time_ago(timedelta(hours=26), "en") == "yesterday"
    assert demo_time_ago(timedelta(days=3), "ko") == "3일 전"


def test_report_and_feedback_use_different_categories():
    """리포트는 `coach_report`, 피드백은 `coach_chat` — 회원앱 목 데이터와 같다(#2085).

    둘이 같은 갈래면 회원 앱 알림함에서 리포트도 말풍선으로 보인다.
    """
    by_title = {n.title: n.category for n in DEMO_NOTIFICATIONS}
    assert by_title["주간 리포트가 도착했어요"] == notification_service.MEMBER_COACH_REPORT
    assert by_title["트레이너 피드백이 도착했어요"] == notification_service.MEMBER_COACH_CHAT


def test_categories_are_known_backend_categories():
    known = {
        "reminder",
        "health_check",
        "achievement",
        "system",
        notification_service.MEMBER_COACH_CHAT,
        notification_service.MEMBER_COACH_REPORT,
        notification_service.MEMBER_ROUTINE,
        notification_service.MEMBER_SCHEDULE,
        notification_service.MEMBER_CONSULTATION,
        notification_service.MEMBER_PT_DONE,
    }
    assert {n.category for n in DEMO_NOTIFICATIONS} <= known
    assert all(len(n.category) <= 20 for n in DEMO_NOTIFICATIONS), "컬럼 길이 20"


def test_pt_completion_alert_uses_the_same_category_as_the_server():
    """실서버가 PT 완료 때 만드는 알림과 같은 갈래다(#3027) — 아이콘·라벨이 같아야 한다."""
    by_title = {n.title: n for n in DEMO_NOTIFICATIONS}
    item = by_title["12회차 PT를 마쳤어요"]
    assert item.category == notification_service.MEMBER_PT_DONE
    assert item.target == "exercise"


def test_pt_done_action_reads_as_a_pt_record():
    assert _action_for(notification_service.MEMBER_PT_DONE, "ko", None).label == "PT 기록 보기"
    assert _action_for(notification_service.MEMBER_PT_DONE, "en", None).label == "View PT record"
    # 데모 알림처럼 목적지가 갈래 표와 같으면 갈래 라벨을 그대로 쓴다.
    assert (
        _action_for(notification_service.MEMBER_PT_DONE, "ko", "exercise").label
        == "PT 기록 보기"
    )


def test_recategorised_demo_alerts_are_backfilled_for_seeded_databases():
    from app.db.seed_notifications import _LEGACY_CATEGORY_BY_ID

    ids = {n.id for n in DEMO_NOTIFICATIONS}
    assert set(_LEGACY_CATEGORY_BY_ID) <= ids
    by_id = {n.id: n.category for n in DEMO_NOTIFICATIONS}
    for nid, legacy in _LEGACY_CATEGORY_BY_ID.items():
        assert by_id[nid] != legacy, "옮긴 뒤 갈래가 예전과 같으면 표에 둘 까닭이 없다"


# ── 문구가 데모 픽스처(김민수)와 같은 사실을 말하는지 ──────────────────────
# 알림은 식단·운동·채팅 목업을 따라 적은 문장이라, 픽스처가 바뀌면 조용히 틀린
# 말을 하게 된다. 요일마다 달라지는 값(주간 운동 시간·리포트 주차)은 문구에 없다.


def _body(title: str) -> str:
    return next(n.body for n in DEMO_NOTIFICATIONS if n.title == title)


def test_seed_has_no_diet_alerts_the_server_never_sends():
    # 실서버에는 식단 기록·나트륨 알림을 만드는 코드가 없다(#2854). 데모에서만 보이면
    # 실서비스로 옮긴 회원에게 기능이 사라진 것으로 보인다.
    text = " ".join(f"{n.title} {n.body}" for n in DEMO_NOTIFICATIONS)
    for word in ("나트륨", "저녁 식단"):
        assert word not in text
    assert all(n.target != "diet" for n in DEMO_NOTIFICATIONS)


def test_removed_diet_alerts_are_cleared_from_seeded_databases():
    # 이미 시드된 데모 DB 에 남은 두 행을 다음 시드가 걷어 낸다.
    assert {"noti-demo-1", "noti-demo-2"} <= set(LEGACY_DEMO_NOTIFICATION_IDS)


def test_routine_alert_names_a_routine_in_the_fixture():
    assert "걷기" in _body("새 개인운동이 왔어요")
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
