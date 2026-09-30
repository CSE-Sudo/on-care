"""운동 기록을 **쓰는** 자리들이 세 날짜 필드를 같은 날로 채우는가. (#1264)

읽는 규칙은 [app.services.exercise_activity] 하나로 모았지만, 규칙만으로는
반쪽이다 — 저장이 `week_start/day_label` 만 채우고 `completed_at` 을 비워 두면,
그 값을 읽는 자리(트레이너 이력·정렬·AI 폴백)에서는 같은 운동이 다른 날이 된다.

여기서 보는 것은 세 갈래다: 회원 수기 기록, 회원의 날짜 수정, PT 완료 파생 기록.
그리고 같은 주를 회원 API 와 트레이너 API 가 같은 수로 읽는지까지 본다.
"""
from __future__ import annotations

from datetime import date, timedelta
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core import clock
from app.models.models import ExerciseSession
from app.services import exercise_activity as activity
from tests.exercise_helpers import post_exercise


def _member_h(client) -> dict:
    """운동 기록이 비어 있는 새 회원. 시드 회원은 기록이 섞여 있어 쓰지 않는다."""
    email = f"exdate-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _trainer_h(client) -> dict:
    token = client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _jisu_h(client) -> dict:
    """트레이너의 담당 고객. 두 API 를 같은 회원으로 견주려면 실 담당 관계가 필요하다."""
    token = client.post(
        "/v1/auth/login",
        data={"username": "jisu@oncare.com", "password": "oncare123"},
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _monday_of(day: date) -> str:
    return (day - timedelta(days=day.weekday())).isoformat()


def _row(db_session, session_id: str) -> ExerciseSession:
    db_session.expire_all()
    row = db_session.get(ExerciseSession, session_id)
    assert row is not None, f"{session_id} 기록이 없다"
    return row


def _assert_all_three_agree(row: ExerciseSession, day: date) -> None:
    """주차·요일·완료 시각이 모두 [day] 를 가리킨다."""
    assert row.week_start == _monday_of(day)
    assert row.day_label == activity.WEEKDAY_LABELS[day.weekday()]
    assert row.completed_at is not None, "완료 시각이 비었다"
    assert clock.to_seoul(row.completed_at).date() == day
    # 세 필드가 같은 날을 가리키니 논리 운동일도 그날 하나다.
    assert activity.activity_date_of(row) == day


def test_manual_session_stores_the_day_it_was_done(client, db_session):
    """어제 한 운동을 오늘 적어도 기록의 날짜는 어제다.

    저장 시각(`clock.now()`)을 `completed_at` 으로 쓰면 회원 화면은 어제로,
    그 값을 읽는 자리는 오늘로 갈린다.
    """
    h = _member_h(client)
    yesterday = clock.today() - timedelta(days=1)
    created = post_exercise(
        client,
        json={
            "type": "cardio", "minutes": 30, "calories": 270,
            "date": yesterday.isoformat(),
        },
        headers=h,
    )
    assert created.status_code == 201, created.text

    _assert_all_three_agree(_row(db_session, created.json()["id"]), yesterday)


def test_moving_a_session_moves_every_date_field(client, db_session):
    """날짜를 고치면 셋이 함께 옮겨 간다 — 하나만 남으면 옛 날짜가 되살아난다."""
    h = _member_h(client)
    today = clock.today()
    moved_to = today - timedelta(days=3)
    session_id = post_exercise(
        client,
        json={
            "type": "strength", "minutes": 40, "calories": 240,
            "date": today.isoformat(),
        },
        headers=h,
    ).json()["id"]

    updated = client.put(
        f"/v1/exercise/sessions/{session_id}",
        json={
            "type": "strength", "minutes": 40, "calories": 240,
            "date": moved_to.isoformat(),
        },
        headers=h,
    )
    assert updated.status_code == 200, updated.text

    _assert_all_three_agree(_row(db_session, session_id), moved_to)


def test_editing_without_a_date_keeps_the_original_day(client, db_session):
    """날짜를 주지 않은 수정은 자리를 옮기지 않는다 — 완료 시각도 그대로다."""
    h = _member_h(client)
    two_days_ago = clock.today() - timedelta(days=2)
    session_id = post_exercise(
        client,
        json={
            "type": "cardio", "minutes": 20, "calories": 180,
            "date": two_days_ago.isoformat(),
        },
        headers=h,
    ).json()["id"]

    client.put(
        f"/v1/exercise/sessions/{session_id}",
        json={"type": "cardio", "minutes": 35, "calories": 315},
        headers=h,
    )

    row = _row(db_session, session_id)
    assert row.minutes == 35
    _assert_all_three_agree(row, two_days_ago)


@pytest.fixture()
def pt_session(client, db_session):
    """PT 슬롯을 만들고 테스트 끝에 지우는 팩토리.

    남겨 두면 회원 이력·주간 집계가 테스트마다 쌓여 다른 테스트가 흔들린다.
    """
    created: list[str] = []
    headers = _trainer_h(client)

    def _make(day: date, **over) -> str:
        body = {
            "date": day.isoformat(), "time": "19:00", "client_name": "이지수",
            "member_id": "user-jisu", "type": "1:1 PT", "duration_minutes": 50,
        }
        body.update(over)
        r = client.post("/v1/trainer/schedule", json=body, headers=headers)
        assert r.status_code == 201, r.text
        created.append(r.json()["id"])
        return created[-1]

    yield _make

    for session_id in created:
        client.delete(f"/v1/trainer/schedule/{session_id}", headers=headers)


def test_pt_completed_today_is_recorded_on_the_session_day(
    client, db_session, pt_session
):
    """지난주 PT 를 오늘 완료 처리해도 회원 기록은 그 세션 날짜에 남는다.

    완료 버튼을 누른 날이 아니라 실제로 수업한 날이 운동일이다 — 완료 시각만
    오늘로 남으면 고객 앱은 지난주에, 그 값을 읽는 쪽은 오늘에 같은 운동을 둔다.
    """
    last_week_day = clock.today() - timedelta(days=7)
    session_id = pt_session(last_week_day)

    done = client.post(
        f"/v1/trainer/schedule/{session_id}/complete",
        json={},
        headers=_trainer_h(client),
    )
    assert done.status_code == 200, done.text

    _assert_all_three_agree(_row(db_session, f"sched-ex-{session_id}"), last_week_day)


def test_pt_derived_record_lands_in_the_members_week(client, pt_session):
    """그 주를 회원 앱으로 열면 PT 가 그 요일에 보인다. 이번 주에는 없다."""
    last_week_day = clock.today() - timedelta(days=7)
    session_id = pt_session(last_week_day, time="19:30", duration_minutes=30)
    client.post(
        f"/v1/trainer/schedule/{session_id}/complete",
        json={},
        headers=_trainer_h(client),
    )

    member = _jisu_h(client)
    that_week = client.get(
        f"/v1/exercise/weeks/current?week_start={_monday_of(last_week_day)}",
        headers=member,
    ).json()
    this_week = client.get("/v1/exercise/weeks/current", headers=member).json()

    derived = [s for s in that_week["sessions"] if s["id"] == f"sched-ex-{session_id}"]
    assert len(derived) == 1, "세션 날짜의 주에 PT 기록이 없다"
    assert derived[0]["date"] == last_week_day.isoformat()
    assert derived[0]["source"] == "trainer_pt"
    assert all(
        s["id"] != f"sched-ex-{session_id}" for s in this_week["sessions"]
    ), "완료 처리한 날의 주로 새어 들어갔다"


#: 두 API 가 **완전히 같아야 하는** 필드. 이행률·코치 문구처럼 화면마다 다른
#: 말을 하는 값은 여기 없다.
_SHARED_FIELDS = (
    "day_labels", "daily_minutes", "daily_calories",
    "cardio_minutes", "strength_minutes", "stretching_minutes", "other_minutes",
    "strength_sets", "total_minutes", "total_calories", "streak_days",
    "weekly_goal_minutes", "weekly_goal_calories",
)


def test_member_and_trainer_read_the_pt_week_the_same(client, pt_session):
    """같은 회원·같은 주를 두 API 가 같은 수로 읽는다.

    데모 픽스처가 아니라 **방금 만든 PT 기록**으로 본다 — 시드 데이터만 견주면
    쓰기 경로가 날짜를 어긋나게 저장해도 두 응답이 나란히 틀려 통과한다.
    """
    last_week_day = clock.today() - timedelta(days=7)
    # 주간 PT 시드(#2452)는 지난 주들의 09:00~19:00 사이에 수업을 깐다(화요일
    # 한지호 18:00~19:00 등). 그 안에 잡으면 실행 요일에 따라 겹침(409)으로
    # 막히므로, 시드가 쓰지 않는 저녁 시간에 둔다.
    session_id = pt_session(last_week_day, time="20:00", duration_minutes=40)
    client.post(
        f"/v1/trainer/schedule/{session_id}/complete",
        json={},
        headers=_trainer_h(client),
    )
    week_start = _monday_of(last_week_day)

    member = client.get(
        f"/v1/exercise/weeks/current?week_start={week_start}", headers=_jisu_h(client)
    )
    trainer = client.get(
        f"/v1/trainer/clients/user-jisu/exercise-week?week_start={week_start}",
        headers=_trainer_h(client),
    )
    assert member.status_code == 200, member.text
    assert trainer.status_code == 200, trainer.text

    left, right = member.json(), trainer.json()
    for field in _SHARED_FIELDS:
        assert left[field] == right[field], field
    assert sorted(
        (s["id"], s["date"], s["minutes"], s["calories"]) for s in left["sessions"]
    ) == sorted(
        (s["id"], s["date"], s["minutes"], s["calories"]) for s in right["sessions"]
    )


def test_legacy_row_without_the_new_fields_still_reads(client, db_session):
    """옛 행은 손대지 않는다 — 폴백만으로 계속 읽혀야 한다.

    쓰기 경로를 고쳤다고 기존 행을 일괄 수정하지 않는다. `completed_at` 이 빈
    채로 남은 기록도 `week_start + day_label` 로 같은 날짜를 낸다.
    """
    h = _member_h(client)
    day = clock.today() - timedelta(days=4)
    session_id = post_exercise(
        client,
        json={
            "type": "other", "minutes": 25, "calories": 125,
            "date": day.isoformat(),
        },
        headers=h,
    ).json()["id"]

    row = _row(db_session, session_id)
    row.completed_at = None  # 이 컬럼을 채우기 전에 저장된 기록의 모양
    db_session.commit()

    body = client.get(
        f"/v1/exercise/weeks/current?week_start={_monday_of(day)}", headers=h
    ).json()
    session = next(s for s in body["sessions"] if s["id"] == session_id)
    assert session["date"] == day.isoformat()
    assert activity.activity_date_of(_row(db_session, session_id)) == day
