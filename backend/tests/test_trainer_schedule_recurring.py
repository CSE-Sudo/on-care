"""반복 PT 일정 — 회차 생성·충돌 검증·멱등·개별 회차 독립성. (#870) DB 필요."""
from __future__ import annotations

from datetime import date, timedelta
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core import clock
from app.models.models import TrainerSchedule
from app.services.trainer import schedule as trainer_schedule_service


def _tok(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def cleanup_sessions(db_session):
    """테스트가 만든 세션을 지운다 — 회원 이력·주간 집계가 쌓이면 다른 테스트가 깨진다."""
    created: list[str] = []
    yield created
    for session_id in created:
        row = db_session.get(TrainerSchedule, session_id)
        if row is not None:
            db_session.delete(row)
    db_session.commit()


def _next_monday() -> date:
    """다음 주 월요일 — 시드 일정이 있는 오늘 주와 겹치지 않는 자리."""
    today = clock.today()
    return today + timedelta(days=(7 - today.weekday()))


def _create(client, token: str, cleanup, **over):
    start = _next_monday()
    body = {
        "date": start.isoformat(),
        "time": "19:00",
        "client_name": "이지수",
        "member_id": "user-jisu",
        "type": "1:1 PT",
        "duration_minutes": 60,
        "weekdays": [1],
        "count": 4,
    }
    body.update(over)
    response = client.post(
        "/v1/trainer/schedule/recurring", json=body, headers=_h(token)
    )
    if response.status_code == 201:
        cleanup.extend(item["id"] for item in response.json())
    return response


def test_weekly_series_creates_every_occurrence(client, cleanup_sessions):
    """한 번의 설정이 8주치를 만든다 — 매주 같은 일정을 다시 입력하지 않는다."""
    token = _tok(client)
    start = _next_monday()

    created = _create(
        client, token, cleanup_sessions, weekdays=[1], count=8, time="19:05"
    )
    assert created.status_code == 201, created.text
    sessions = created.json()
    assert len(sessions) == 8
    assert [item["date"] for item in sessions] == [
        (start + timedelta(days=7 * week)).isoformat() for week in range(8)
    ]
    assert {item["time"] for item in sessions} == {"19:05"}
    assert {item["status"] for item in sessions} == {"예정"}


def test_two_days_a_week_alternate_in_order(client, cleanup_sessions):
    """주 2회(월·목)도 한 번에 잡힌다."""
    token = _tok(client)
    start = _next_monday()

    created = _create(
        client, token, cleanup_sessions, weekdays=[1, 4], count=4, time="19:10"
    )
    assert created.status_code == 201, created.text
    dates = [date.fromisoformat(item["date"]) for item in created.json()]
    assert [day.isoweekday() for day in dates] == [1, 4, 1, 4]
    assert dates[0] == start


def test_end_by_date_stops_at_the_last_matching_day(client, cleanup_sessions):
    """종료일 기준 반복은 그 날짜를 넘기지 않는다(종료일 포함)."""
    token = _tok(client)
    start = _next_monday()
    until = start + timedelta(days=14)

    created = _create(
        client,
        token,
        cleanup_sessions,
        weekdays=[1],
        count=None,
        until=until.isoformat(),
        time="19:15",
    )
    assert created.status_code == 201, created.text
    dates = [item["date"] for item in created.json()]
    assert dates == [
        start.isoformat(),
        (start + timedelta(days=7)).isoformat(),
        until.isoformat(),
    ]


def test_preview_shows_the_occurrences_before_saving(client):
    """저장 전에 생성될 회차를 확인할 수 있다 — 아무것도 만들지 않는다."""
    token = _tok(client)
    start = _next_monday()
    body = {
        "date": start.isoformat(),
        "time": "19:20",
        "client_name": "이지수",
        "member_id": "user-jisu",
        "type": "1:1 PT",
        "duration_minutes": 60,
        "weekdays": [1, 3],
        "count": 6,
    }
    preview = client.post(
        "/v1/trainer/schedule/recurring/preview", json=body, headers=_h(token)
    )
    assert preview.status_code == 200, preview.text
    assert len(preview.json()["dates"]) == 6
    assert preview.json()["conflicts"] == []
    # 키 없이 부르면 예전과 같다 — 새 칸은 기본값으로 채워진다(#3102).
    assert preview.json()["already_created"] is False

    listed = client.get(
        "/v1/trainer/schedule",
        params={"date": start.isoformat()},
        headers=_h(token),
    ).json()
    assert not [item for item in listed if item["time"] == "19:20"]


def test_conflicting_series_creates_nothing(client, cleanup_sessions, db_session):
    """겹치는 회차가 있으면 전부 멈춘다 — 일부만 조용히 만들지 않는다."""
    token = _tok(client)
    start = _next_monday()
    blocker = client.post(
        "/v1/trainer/schedule",
        json={
            "date": (start + timedelta(days=7)).isoformat(),
            "time": "19:25",
            "client_name": "박성호",
            "type": "1:1 PT",
            "duration_minutes": 60,
        },
        headers=_h(token),
    )
    assert blocker.status_code == 201, blocker.text
    cleanup_sessions.append(blocker.json()["id"])

    blocked = _create(
        client, token, cleanup_sessions, weekdays=[1], count=4, time="19:25"
    )
    assert blocked.status_code == 409, blocked.text
    detail = blocked.json()["detail"]
    # 화면이 "총 4회 중 1개가 겹칩니다" 를 그리려면 겹친 회차를 짚어 줘야 한다.
    assert len(detail["conflicts"]) == 1
    assert detail["conflicts"][0]["date"] == (start + timedelta(days=7)).isoformat()

    # 하나도 만들어지지 않았다.
    rows = db_session.scalars(
        select(TrainerSchedule).where(
            TrainerSchedule.trainer_id == "trainer-demo",
            TrainerSchedule.time == "19:25",
        )
    ).all()
    assert len(rows) == 1
    assert rows[0].id == blocker.json()["id"]


def test_cancelled_session_does_not_block_a_new_series(client, cleanup_sessions):
    """취소된 자리는 비어 있다 — 그 시간에 다시 잡을 수 있다(#871과의 접점)."""
    token = _tok(client)
    start = _next_monday()
    booked = client.post(
        "/v1/trainer/schedule",
        json={
            "date": start.isoformat(),
            "time": "19:30",
            "client_name": "박성호",
            "type": "1:1 PT",
            "duration_minutes": 60,
        },
        headers=_h(token),
    )
    assert booked.status_code == 201, booked.text
    cleanup_sessions.append(booked.json()["id"])
    cancelled = client.post(
        f"/v1/trainer/schedule/{booked.json()['id']}/cancel",
        json={"source": "member"},
        headers=_h(token),
    )
    assert cancelled.status_code == 200, cancelled.text

    created = _create(
        client, token, cleanup_sessions, weekdays=[1], count=2, time="19:30"
    )
    assert created.status_code == 201, created.text


def test_retrying_the_same_request_creates_one_series(client, cleanup_sessions):
    """끊긴 응답으로 재시도한 등록이 회차를 두 벌 만들지 않는다."""
    token = _tok(client)
    request_id = f"req-{uuid4().hex[:10]}"

    first = _create(
        client,
        token,
        cleanup_sessions,
        weekdays=[1],
        count=3,
        time="19:35",
        client_request_id=request_id,
    )
    assert first.status_code == 201, first.text
    second = _create(
        client,
        token,
        cleanup_sessions,
        weekdays=[1],
        count=3,
        time="19:35",
        client_request_id=request_id,
    )
    assert second.status_code == 201, second.text
    assert [item["id"] for item in second.json()] == [
        item["id"] for item in first.json()
    ]


def _preview(client, token: str, **over):
    body = {
        "date": _next_monday().isoformat(),
        "time": "19:00",
        "client_name": "이지수",
        "member_id": "user-jisu",
        "type": "1:1 PT",
        "duration_minutes": 60,
        "weekdays": [1],
        "count": 4,
    }
    body.update(over)
    return client.post(
        "/v1/trainer/schedule/recurring/preview", json=body, headers=_h(token)
    )


def test_preview_with_the_same_key_skips_its_own_series(client, cleanup_sessions):
    """만들기는 커밋됐는데 응답만 잃은 재시도 — 미리보기가 자기 회차와 겹친다고
    막지 않고 `already_created` 로 알려, 같은 키로 만들기를 다시 부르게 한다(#3102)."""
    token = _tok(client)
    request_id = f"req-{uuid4().hex[:10]}"
    first = _create(
        client, token, cleanup_sessions,
        weekdays=[1, 3], count=4, time="19:40", client_request_id=request_id,
    )
    assert first.status_code == 201, first.text

    same = _preview(
        client, token,
        weekdays=[1, 3], count=4, time="19:40", client_request_id=request_id,
    )
    assert same.status_code == 200, same.text
    assert same.json()["conflicts"] == []
    assert same.json()["already_created"] is True

    retried = _create(
        client, token, cleanup_sessions,
        weekdays=[1, 3], count=4, time="19:40", client_request_id=request_id,
    )
    assert retried.status_code == 201, retried.text
    assert [item["id"] for item in retried.json()] == [
        item["id"] for item in first.json()
    ]


def test_preview_with_another_key_still_reports_the_series(client, cleanup_sessions):
    """다른 시도(다른 키·키 없음)에게 그 회차는 여전히 차 있는 자리다."""
    token = _tok(client)
    created = _create(
        client, token, cleanup_sessions,
        weekdays=[1], count=2, time="19:45",
        client_request_id=f"req-{uuid4().hex[:10]}",
    )
    assert created.status_code == 201, created.text
    own_ids = {item["id"] for item in created.json()}

    for extra in ({"client_request_id": f"req-{uuid4().hex[:10]}"}, {}):
        other = _preview(
            client, token, weekdays=[1], count=2, time="19:45", **extra
        )
        assert other.status_code == 200, other.text
        assert {item["id"] for item in other.json()["conflicts"]} == own_ids
        assert other.json()["already_created"] is False


def test_one_occurrence_moves_without_touching_the_others(
    client, cleanup_sessions
):
    """반복으로 만들어졌어도 회차 하나만 옮길 수 있다 — 실제 운영이 그렇다."""
    token = _tok(client)
    created = _create(
        client, token, cleanup_sessions, weekdays=[1], count=3, time="19:40"
    )
    assert created.status_code == 201, created.text
    sessions = created.json()

    moved = client.put(
        f"/v1/trainer/schedule/{sessions[1]['id']}",
        json={"time": "20:40"},
        headers=_h(token),
    )
    assert moved.status_code == 200, moved.text
    assert moved.json()["time"] == "20:40"

    others = client.get(
        "/v1/trainer/schedule",
        params={"date": sessions[0]["date"]},
        headers=_h(token),
    ).json()
    kept = next(item for item in others if item["id"] == sessions[0]["id"])
    assert kept["time"] == "19:40"


def test_one_occurrence_is_deleted_alone(client, cleanup_sessions, db_session):
    """특정 회차만 지워도 나머지 반복은 남는다."""
    token = _tok(client)
    created = _create(
        client, token, cleanup_sessions, weekdays=[1], count=3, time="19:45"
    )
    assert created.status_code == 201, created.text
    sessions = created.json()

    deleted = client.delete(
        f"/v1/trainer/schedule/{sessions[0]['id']}", headers=_h(token)
    )
    assert deleted.status_code == 200, deleted.text

    db_session.expire_all()
    assert db_session.get(TrainerSchedule, sessions[0]["id"]) is None
    for remaining in sessions[1:]:
        assert db_session.get(TrainerSchedule, remaining["id"]) is not None


def test_series_is_capped(client, cleanup_sessions):
    """종료일에 연도를 잘못 적어도 수백 건이 조용히 생기지 않는다."""
    token = _tok(client)
    start = _next_monday()
    created = _create(
        client,
        token,
        cleanup_sessions,
        weekdays=[1, 2, 3, 4, 5],
        count=None,
        until=(start + timedelta(days=365 * 3)).isoformat(),
        time="19:50",
    )
    assert created.status_code == 201, created.text
    assert len(created.json()) == trainer_schedule_service.MAX_SERIES_OCCURRENCES


def test_invalid_recurrence_is_rejected(client):
    """요일 없이, 또는 종료 기준 없이(둘 다 주고) 반복을 만들 수 없다."""
    token = _tok(client)
    start = _next_monday().isoformat()
    base = {
        "date": start,
        "time": "19:55",
        "client_name": "이지수",
        "member_id": "user-jisu",
        "type": "1:1 PT",
        "duration_minutes": 60,
    }
    for payload in (
        {**base, "weekdays": [], "count": 4},
        {**base, "weekdays": [1]},
        {**base, "weekdays": [1], "count": 4, "until": start},
        {**base, "weekdays": [8], "count": 4},
        {**base, "weekdays": [1], "until": "2020-01-01"},
    ):
        response = client.post(
            "/v1/trainer/schedule/recurring", json=payload, headers=_h(token)
        )
        assert response.status_code == 422, response.text


def test_recurring_needs_the_client_link(client):
    """담당하지 않는 회원에게는 반복 일정을 잡을 수 없다."""
    token = _tok(client)
    response = client.post(
        "/v1/trainer/schedule/recurring",
        json={
            "date": _next_monday().isoformat(),
            "time": "19:58",
            "client_name": "남의 고객",
            "member_id": f"user-{uuid4().hex[:8]}",
            "type": "1:1 PT",
            "duration_minutes": 60,
            "weekdays": [1],
            "count": 2,
        },
        headers=_h(token),
    )
    assert response.status_code == 404, response.text
