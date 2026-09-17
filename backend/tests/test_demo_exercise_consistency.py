"""데모 회원의 한 주 운동을 회원 앱과 트레이너 화면이 같은 수로 읽는가. (#1265)

숫자의 기준은 **고객 앱 운동 계약**이다. 트레이너 API 는 그 값을 다시 해석하지
않는다 — 두 화면을 나란히 놓고 시연하는 것이 이 데모의 전부라, 같은 회원의 같은
날에 두 앱이 다른 수를 말하면 데모가 성립하지 않는다.

두 응답이 실제로 같은지는 **응답을 직접 견주어** 확인한다. 같은 함수를 부르니까
같을 것이라고 두면, 한쪽 라우터에 필터가 하나 붙는 순간 조용히 갈라진다.
"""
from __future__ import annotations

from datetime import timedelta

import pytest

from app.core import clock
from app.db.demo_fixture import load_fixture
from app.services.exercise_service import monday_of_str

#: 두 API 가 **완전히 같아야 하는** 필드. 이행률·코치 문구처럼 화면마다 다른
#: 말을 하는 값은 여기 없다.
_SHARED_FIELDS = (
    "day_labels",
    "daily_minutes",
    "daily_calories",
    "cardio_minutes",
    "strength_minutes",
    "stretching_minutes",
    "other_minutes",
    "strength_sets",
    "total_minutes",
    "total_calories",
    "streak_days",
    "weekly_goal_minutes",
    "weekly_goal_calories",
)

#: 세션 한 줄에서 견주는 값.
_SESSION_FIELDS = ("date", "type", "minutes", "calories", "sets", "reps")


def _trainer_token(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "trainer@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _member_token(client) -> str:
    return client.post(
        "/v1/auth/login",
        data={"username": "minsu@oncare.com", "password": "oncare123"},
    ).json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _sessions(body: dict) -> list[tuple]:
    """세션을 견주기 좋은 모양으로. 순서는 응답마다 다를 수 있어 정렬한다."""
    return sorted(
        tuple(session[field] for field in _SESSION_FIELDS)
        for session in body["sessions"]
    )


def _weeks_to_check() -> list[str]:
    """이번 주 · 지난주 · 과거 PT 가 있는 주.

    오늘은 **서비스 기준 시각(KST)** 으로 센다. 시드가 그 시계로 날짜를 붙이는데
    여기서 러너의 로컬 날짜를 쓰면, UTC 저녁(=KST 다음 날)에 도는 CI 에서 서로 다른
    하루를 가리킨다. (#557)
    """
    fixture = load_fixture()
    today = clock.today()
    weeks = [
        monday_of_str(today.isoformat()),
        monday_of_str((today - timedelta(days=7)).isoformat()),
    ]
    pt_days = [day for day in fixture.days_for(today) if day.is_pt and day.day < today]
    if pt_days:
        weeks.append(pt_days[-1].week_start)
    return weeks


@pytest.mark.parametrize("week_start", _weeks_to_check())
def test_member_and_trainer_read_the_same_week(client, week_start):
    member_id = load_fixture().user_app_seed_id
    member = client.get(
        f"/v1/exercise/weeks/current?week_start={week_start}",
        headers=_auth(_member_token(client)),
    )
    trainer = client.get(
        f"/v1/trainer/clients/{member_id}/exercise-week?week_start={week_start}",
        headers=_auth(_trainer_token(client)),
    )
    assert member.status_code == 200, member.text
    assert trainer.status_code == 200, trainer.text

    left, right = member.json(), trainer.json()
    for field in _SHARED_FIELDS:
        assert left[field] == right[field], f"{week_start} · {field}"
    assert _sessions(left) == _sessions(right), week_start


def test_the_week_totals_are_the_sum_of_their_days(client):
    """합계가 요일 값에서 나온다 — 둘이 갈라지면 어느 쪽이 진짜인지 알 수 없다."""
    body = client.get(
        "/v1/exercise/weeks/current",
        headers=_auth(_member_token(client)),
    ).json()
    assert body["total_minutes"] == sum(body["daily_minutes"])
    assert body["total_calories"] == sum(body["daily_calories"])
    for index in range(7):
        assert body["daily_minutes"][index] == (
            body["cardio_minutes"][index]
            + body["strength_minutes"][index]
            + body["stretching_minutes"][index]
            + body["other_minutes"][index]
        ), f"{index} 요일 합이 유형별 합과 다르다"


def test_seeded_strength_keeps_the_sets_the_fixture_wrote(client):
    """근력 기록의 세트는 픽스처가 적은 값이다 — 분에서 되짚은 수가 아니다.

    예전에는 백엔드가 픽스처의 `sets` 를 버려서, 같은 날 근력이 회원 앱(픽스처
    값)과 실 API(분 ÷ 3)에서 다른 수로 보였다.
    """
    fixture = load_fixture()
    today = clock.today()
    day = next(
        d
        for d in reversed(fixture.days_for(today))
        if any(e.type == "strength" and e.sets for e in d.done_exercises)
    )
    expected = sum(
        e.sets or 0 for e in day.done_exercises if e.type == "strength"
    )

    body = client.get(
        f"/v1/exercise/weeks/current?week_start={day.week_start}",
        headers=_auth(_member_token(client)),
    ).json()
    strength = [
        s
        for s in body["sessions"]
        if s["type"] == "strength" and s["date"] == day.iso
    ]
    assert strength, f"{day.iso} 근력 기록이 없다"
    # 기록 한 행이 운동 하나다(#1902) — 그날 근력 세트의 **합**을 견준다. 예전에는
    # 하루·유형으로 묶여 한 행에 합계가 들어 있었다.
    assert sum(s["sets"] or 0 for s in strength) == expected
