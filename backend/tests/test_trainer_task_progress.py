"""대시보드 `오늘 할 일` 진행 상태의 계정 단위 저장. (#1633) DB 필요."""
from __future__ import annotations

from datetime import timedelta

import pytest
from sqlalchemy import delete, select

from app.core import clock
from app.models.models import TrainerDailyTaskProgress, User
from app.services.trainer_task_progress_service import RETENTION_DAYS

_BASE = "/v1/trainer/dashboard/task-progress"
_BODY = {
    "total": 3,
    "completed_today": 1,
    "completed_carried_over": 0,
    "pending_keys": ["report-b", "report-a"],
    "dismissed_keys": ["program-c"],
    "completed_keys": ["alert-d"],
}


@pytest.fixture(autouse=True)
def _clear_progress(db_session):
    """테스트마다 이 트레이너의 진행 기록을 비운다.

    DB 는 세션 동안 공유되고 모든 테스트가 같은 데모 트레이너로 쓴다. 키 단위
    변경은 화면이 모르는 기존 키를 보존하므로(#2886), 앞 테스트가 저장한 그날의
    체크·삭제 키가 남아 있으면 뒤 테스트의 결과에 섞인다.
    """
    trainer_id = db_session.scalar(
        select(User.id).where(User.email == "trainer@oncare.com")
    )
    db_session.execute(
        delete(TrainerDailyTaskProgress).where(
            TrainerDailyTaskProgress.trainer_id == trainer_id
        )
    )
    db_session.commit()
    yield


def _token(client) -> dict:
    res = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    )
    assert res.status_code == 200, res.text
    return {"Authorization": f"Bearer {res.json()['access_token']}"}


def test_saved_day_is_read_back_from_another_login(client):
    today = clock.today_iso()
    saved = client.put(f"{_BASE}/{today}", json=_BODY, headers=_token(client))
    assert saved.status_code == 200, saved.text

    # 새로 로그인한 다른 기기에서도 같은 체크·삭제 상태가 보인다.
    days = client.get(_BASE, headers=_token(client)).json()["days"]
    day = next(d for d in days if d["date"] == today)
    assert day["pending_keys"] == ["report-a", "report-b"]
    assert day["dismissed_keys"] == ["program-c"]
    # 체크한 키는 추정하지 않고 저장한 그대로 돌아온다(#1716).
    assert day["completed_keys"] == ["alert-d"]


def test_only_server_today_or_yesterday_is_writable(client):
    headers = _token(client)
    today = clock.today()
    yesterday = (today - timedelta(days=1)).isoformat()
    assert client.put(f"{_BASE}/{yesterday}", json=_BODY, headers=headers).status_code == 200
    for day in ((today - timedelta(days=2)).isoformat(), "20260101"):
        assert client.put(f"{_BASE}/{day}", json=_BODY, headers=headers).status_code == 422


def test_rows_past_retention_are_pruned_on_write(client, db_session):
    headers = _token(client)
    trainer_id = db_session.scalar(
        select(User.id).where(User.email == "trainer@oncare.com")
    )
    today = clock.today()
    expired = (today - timedelta(days=RETENTION_DAYS)).isoformat()
    kept = (today - timedelta(days=RETENTION_DAYS - 1)).isoformat()
    for day in (expired, kept):
        db_session.merge(TrainerDailyTaskProgress(trainer_id=trainer_id, date=day, total=1))
    db_session.commit()

    assert client.put(f"{_BASE}/{today.isoformat()}", json=_BODY, headers=headers).status_code == 200
    dates = [d["date"] for d in client.get(_BASE, headers=headers).json()["days"]]
    assert expired not in dates and kept in dates


# ---- 키 단위 변경 (#2886) -------------------------------------------------

_KEYS = f"{_BASE}/{{day}}/keys"


def _change(client, headers, day, key, action, *, keys=(), seen=()):
    return client.post(
        _KEYS.format(day=day),
        json={"key": key, "action": action, "keys": list(keys), "seen": list(seen)},
        headers=headers,
    )


def _day(client, headers, day):
    days = client.get(_BASE, headers=headers).json()["days"]
    return next(d for d in days if d["date"] == day)


def test_two_tabs_checking_different_keys_both_survive(client):
    """탭 A 가 할 일 1, 탭 B(옛 상태) 가 할 일 2 를 체크해도 둘 다 남는다."""
    today = clock.today_iso()
    tab_a, tab_b = _token(client), _token(client)
    keys = ["report-a", "report-b", "report-c"]

    res_a = _change(client, tab_a, today, "report-a", "check", keys=keys, seen=keys)
    assert res_a.status_code == 200, res_a.text
    # 탭 B 는 A 의 체크를 모른 채 자기 키만 보낸다.
    res_b = _change(client, tab_b, today, "report-b", "check", keys=keys, seen=keys)
    assert res_b.status_code == 200, res_b.text

    day = _day(client, tab_a, today)
    assert sorted(day["completed_keys"]) == ["report-a", "report-b"]
    assert day["pending_keys"] == ["report-c"]
    assert day["total"] == 3
    assert day["completed_today"] == 2
    # 응답은 반영 뒤의 그날 상태라, 탭 B 도 A 의 체크를 받는다.
    assert sorted(res_b.json()["completed_keys"]) == ["report-a", "report-b"]


def test_dismissed_key_is_not_revived_by_another_tab(client):
    today = clock.today_iso()
    tab_a, tab_b = _token(client), _token(client)
    keys = ["report-a", "report-b"]

    assert _change(client, tab_a, today, "report-a", "dismiss", keys=keys, seen=keys).status_code == 200
    # 탭 B 는 아직 report-a 를 보여 주는 옛 화면이다.
    res = _change(client, tab_b, today, "report-b", "check", keys=keys, seen=keys)
    assert res.status_code == 200, res.text

    day = res.json()
    assert day["dismissed_keys"] == ["report-a"]
    assert "report-a" not in day["pending_keys"]
    assert "report-a" not in day["completed_keys"]
    assert day["total"] == 1


def test_uncheck_removes_only_that_key(client):
    today = clock.today_iso()
    headers = _token(client)
    keys = ["report-a", "report-b"]
    _change(client, headers, today, "report-a", "check", keys=keys, seen=keys)
    _change(client, headers, today, "report-b", "check", keys=keys, seen=keys)

    day = _change(client, headers, today, "report-a", "uncheck", keys=keys, seen=keys).json()

    assert day["completed_keys"] == ["report-b"]
    assert day["pending_keys"] == ["report-a"]


def test_completed_count_never_exceeds_total(client):
    today = clock.today_iso()
    headers = _token(client)
    # 화면이 본 적 있는데 지금은 사라진 키(처리한 상담)는 목록에서 빠지고,
    # 그 키의 완료도 함께 빠진다.
    _change(client, headers, today, "consultation-x", "check",
            keys=["consultation-x", "report-a"], seen=["consultation-x", "report-a"])
    day = _change(client, headers, today, "report-a", "check",
                  keys=["report-a"], seen=["consultation-x", "report-a"]).json()

    assert day["completed_keys"] == ["report-a"]
    assert day["total"] == 1
    assert day["completed_today"] + day["completed_carried_over"] <= day["total"]


def test_keys_unknown_to_the_screen_are_kept(client):
    """다른 탭에만 보이는 미션(늦게 온 상담)의 체크는 이 탭의 변경으로 지워지지 않는다."""
    today = clock.today_iso()
    tab_a, tab_b = _token(client), _token(client)
    _change(client, tab_a, today, "consultation-new", "check",
            keys=["consultation-new", "report-a"], seen=["consultation-new", "report-a"])

    day = _change(client, tab_b, today, "report-a", "check",
                  keys=["report-a"], seen=["report-a"]).json()

    assert sorted(day["completed_keys"]) == ["consultation-new", "report-a"]
    assert day["total"] == 2


def test_carried_over_completion_is_counted_from_previous_day(client):
    headers = _token(client)
    today = clock.today()
    yesterday = (today - timedelta(days=1)).isoformat()
    # 어제 끝내지 못한 report-a.
    _change(client, headers, yesterday, "report-b", "check",
            keys=["report-a", "report-b"], seen=["report-a", "report-b"])

    day = _change(client, headers, today.isoformat(), "report-a", "check",
                  keys=["report-a", "report-c"], seen=["report-a", "report-c"]).json()

    assert day["completed_carried_over"] == 1
    assert day["completed_today"] == 0
    assert day["total"] == 2


def test_key_change_only_accepts_today_or_yesterday(client):
    headers = _token(client)
    too_old = (clock.today() - timedelta(days=2)).isoformat()
    for day in (too_old, "20260101"):
        res = _change(client, headers, day, "report-a", "check", keys=["report-a"])
        assert res.status_code == 422


def test_key_change_rejects_unknown_action(client):
    res = _change(client, _token(client), clock.today_iso(), "report-a", "toggle")
    assert res.status_code == 422


def test_key_change_on_a_legacy_row_keeps_other_fields(client, db_session):
    """체크 키 기록 이전(#1716)의 행에서도 지운 키와 미완료 목록을 잃지 않는다."""
    headers = _token(client)
    trainer_id = db_session.scalar(
        select(User.id).where(User.email == "trainer@oncare.com")
    )
    today = clock.today_iso()
    db_session.merge(
        TrainerDailyTaskProgress(
            trainer_id=trainer_id,
            date=today,
            total=2,
            pending_keys_json='["report-a", "report-b"]',
            dismissed_keys_json='["program-c"]',
            completed_keys_json=None,
        )
    )
    db_session.commit()

    day = _change(client, headers, today, "report-a", "check",
                  keys=["report-a"], seen=["report-a"]).json()

    assert day["completed_keys"] == ["report-a"]
    assert day["dismissed_keys"] == ["program-c"]
    # 화면이 본 적 없는 report-b 는 그대로 미완료다.
    assert day["pending_keys"] == ["report-b"]
