"""대시보드 `오늘 할 일` 진행 상태의 계정 단위 저장. (#1633) DB 필요."""
from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select

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
}


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
