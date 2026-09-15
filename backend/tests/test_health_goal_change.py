"""건강 목표 변경 기록과 상대 알림. (#1832) DB 필요.

회원과 담당 트레이너가 같은 건강 목표 칸을 고친다. 승인 대신 바로 적용하고, 상대에게
알리고, 누가 언제 바꿨는지 남긴다. 목표 칩이 실제로 바뀐 저장에만 그렇게 한다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest
from sqlalchemy import delete, select

from app.models.models import HealthProfile, Notification, User
from app.services import health_goal_change, notification_service

MEMBER_ID = "user-jisu"


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str, password: str = "oncare123") -> str:
    return client.post(
        "/v1/auth/login", data={"username": email, "password": password}
    ).json()["access_token"]


@pytest.fixture
def seeded(client, db_session):
    """시드 트레이너와 담당 회원(지수). 끝나면 목표·기록·이 테스트가 만든 알림을 되돌린다."""
    trainer_id = db_session.scalar(
        select(User.id).where(User.email == "trainer@oncare.com")
    )
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == MEMBER_ID)
    )
    original = (
        profile.conditions,
        profile.daily_calories,
        profile.focus_changed_by,
        profile.focus_changed_by_id,
        profile.focus_changed_at,
    )
    yield {
        "trainer": _login(client, "trainer@oncare.com"),
        "member": _login(client, "jisu@oncare.com"),
        "trainer_id": trainer_id,
    }
    db_session.expire_all()
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == MEMBER_ID)
    )
    (
        profile.conditions,
        profile.daily_calories,
        profile.focus_changed_by,
        profile.focus_changed_by_id,
        profile.focus_changed_at,
    ) = original
    db_session.execute(
        delete(Notification).where(
            Notification.category.in_(
                [
                    notification_service.MEMBER_HEALTH_GOALS,
                    notification_service.TRAINER_HEALTH_GOAL_KIND,
                ]
            )
        )
    )
    db_session.commit()


def _goal_notices(client, token: str, *, trainer: bool) -> list[dict]:
    path = "/v1/trainer/notifications" if trainer else "/v1/notifications"
    res = client.get(path, headers=_h(token))
    assert res.status_code == 200, res.text
    category = (
        notification_service.TRAINER_HEALTH_GOAL_KIND
        if trainer
        else notification_service.MEMBER_HEALTH_GOALS
    )
    return [n for n in res.json() if n["category"] == category]


@pytest.mark.parametrize(
    ("before", "after", "changed"),
    [
        ("체중 감량, 체력 강화", "체력 강화, 체중 감량", False),
        ("체중 감량, 무릎 통증 주의", "체중 감량, 러닝 자제", False),
        ("체중 감량", "체중 감량, 혈압 관리", True),
        ("체중 감량", "", True),
        ("", "재활", True),
        (None, "", False),
    ],
)
def test_only_a_different_goal_set_counts_as_a_change(before, after, changed):
    assert health_goal_change.focus_changed(before, after) is changed


def test_member_change_is_recorded_and_the_trainer_is_told(client, seeded):
    saved = client.put(
        "/v1/users/me/health-goals",
        headers=_h(seeded["member"]),
        json={"conditions": "근력 향상, 재활"},
    )
    assert saved.status_code == 200, saved.text
    body = saved.json()
    assert body["focus_changed_by"] == "member"
    assert body["focus_changed_at"] is not None

    notices = _goal_notices(client, seeded["trainer"], trainer=True)
    assert len(notices) == 1
    assert notices[0]["subject_id"] == MEMBER_ID
    assert notices[0]["title"] == "회원 건강 목표 변경"
    assert notices[0]["body"].endswith("건강 목표를 바꿨어요: 근력 향상 · 재활")

    # 트레이너 창에도 같은 마지막 변경이 보인다.
    trainer_view = client.get(
        f"/v1/trainer/clients/{MEMBER_ID}/health-profile", headers=_h(seeded["trainer"])
    ).json()
    assert trainer_view["focus_changed_by"] == "member"
    assert trainer_view["focus_changed_at"] == body["focus_changed_at"]
    # 회원 자신에게는 알리지 않는다.
    assert _goal_notices(client, seeded["member"], trainer=False) == []


def test_saves_that_do_not_change_the_goal_set_stay_quiet(client, seeded, db_session):
    current = client.get("/v1/users/me/profile", headers=_h(seeded["member"])).json()
    goals = ", ".join(reversed(current["conditions"].split(", ")))

    numbers_only = client.put(
        "/v1/users/me/health-goals",
        headers=_h(seeded["member"]),
        json={"daily_calories": 1900},
    )
    assert numbers_only.status_code == 200, numbers_only.text
    reordered = client.put(
        "/v1/users/me/health-goals",
        headers=_h(seeded["member"]),
        json={"conditions": goals},
    )
    assert reordered.status_code == 200, reordered.text

    assert reordered.json()["focus_changed_at"] == current["focus_changed_at"]
    assert _goal_notices(client, seeded["trainer"], trainer=True) == []


def test_trainer_change_is_recorded_and_the_member_is_told(client, seeded):
    saved = client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/health-profile",
        headers=_h(seeded["trainer"]),
        json={"conditions": "자세 교정, 무릎 통증으로 러닝 자제"},
    )
    assert saved.status_code == 200, saved.text
    assert saved.json()["focus_changed_by"] == "trainer"

    notices = _goal_notices(client, seeded["member"], trainer=False)
    assert len(notices) == 1
    assert notices[0]["title"] == "건강 목표가 바뀌었어요"
    assert notices[0]["body"].endswith("트레이너님이 건강 목표를 바꿨어요: 자세 교정")
    # 누르면 MY 건강 목표로 간다.
    assert notices[0]["action"] == {"label": "목표 보기", "target": "health_goals"}

    member_view = client.get("/v1/users/me/profile", headers=_h(seeded["member"])).json()
    assert member_view["focus_changed_by"] == "trainer"
    assert _goal_notices(client, seeded["trainer"], trainer=True) == []


def test_trainer_saving_other_fields_does_not_count(client, seeded):
    saved = client.put(
        f"/v1/trainer/clients/{MEMBER_ID}/health-profile",
        headers=_h(seeded["trainer"]),
        json={"daily_calories": 2100},
    )
    assert saved.status_code == 200, saved.text
    assert _goal_notices(client, seeded["member"], trainer=False) == []


def test_member_without_trainer_only_records(client, db_session):
    email = f"goal-{uuid4().hex[:10]}@oncare.com"
    r = client.post(
        "/v1/auth/register", json={"email": email, "password": "goal-pw-123", "name": "목표"}
    )
    assert r.status_code == 201, r.text
    token = _login(client, email, "goal-pw-123")

    onboarded = client.post(
        "/v1/users/me/onboarding", headers=_h(token), json={"conditions": "운동 습관"}
    )
    assert onboarded.status_code == 200, onboarded.text
    assert onboarded.json()["focus_changed_by"] == "member"

    none_left = client.put(
        "/v1/users/me/health-goals", headers=_h(token), json={"conditions": ""}
    )
    assert none_left.status_code == 200, none_left.text
    assert none_left.json()["focus_changed_by"] == "member"
    count = db_session.scalar(
        select(Notification.id).where(
            Notification.category == notification_service.TRAINER_HEALTH_GOAL_KIND,
            Notification.subject_id == r.json()["id"],
        )
    )
    assert count is None
