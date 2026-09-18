"""회원이 이름을 바꾸면 담당 트레이너에게 한 번 알린다. (#2065) DB 필요.

알림은 만든 순간의 이름을 글자로 담는다. 이미 받은 알림은 그때 이름으로 남고, 바꾼
뒤의 알림부터 새 이름을 쓴다 — 받은 순간의 기록이라 고쳐 쓰지 않는다. 대신 이름이
바뀐 사실을 한 번 알려, 트레이너 알림함의 옛 이름과 회원 목록의 새 이름을 잇는다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest
from sqlalchemy import delete, select

from app.models.models import Notification, User
from app.services import notification_service

MEMBER_ID = "user-jisu"


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str, password: str = "oncare123") -> str:
    response = client.post(
        "/v1/auth/login", data={"username": email, "password": password}
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _name_notices(client, trainer_token: str) -> list[dict]:
    response = client.get("/v1/trainer/notifications", headers=_h(trainer_token))
    assert response.status_code == 200, response.text
    return [
        n
        for n in response.json()
        if n["category"] == notification_service.TRAINER_MEMBER_NAME_KIND
    ]


@pytest.fixture
def seeded(client, db_session):
    """시드 트레이너와 담당 회원(지수). 끝나면 이름과 이 테스트가 만든 알림을 되돌린다.

    이름은 API 가 아니라 DB 로 되돌린다 — API 로 되돌리면 그 자체가 또 알림을 만든다.
    """
    original = db_session.get(User, MEMBER_ID).name
    yield {
        "trainer": _login(client, "trainer@oncare.com"),
        "member": _login(client, "jisu@oncare.com"),
        "original": original,
    }
    db_session.expire_all()
    db_session.get(User, MEMBER_ID).name = original
    db_session.execute(
        delete(Notification).where(
            Notification.category == notification_service.TRAINER_MEMBER_NAME_KIND
        )
    )
    db_session.commit()


def test_renaming_tells_the_trainer_once(client, seeded):
    """옛 이름과 새 이름을 함께 적어, 알림함의 옛 이름과 목록의 새 이름을 잇는다."""
    response = client.put(
        "/v1/users/me", headers=_h(seeded["member"]), json={"name": "이수진"}
    )
    assert response.status_code == 200, response.text

    notices = _name_notices(client, seeded["trainer"])
    assert len(notices) == 1
    assert notices[0]["title"] == "회원 이름 변경"
    assert notices[0]["body"] == f"{seeded['original']} 회원이 이름을 바꿨어요: 이수진"
    # 누르면 그 회원 상세로 간다 — 건강 목표 변경 알림과 같은 길이다.
    assert notices[0]["subject_id"] == MEMBER_ID


def test_saving_the_same_name_stays_quiet(client, seeded):
    """이름이 그대로인 저장(같은 이름, 앞뒤 공백만 다른 이름)은 알리지 않는다."""
    for body in (
        {"name": seeded["original"]},
        {"name": f"  {seeded['original']}  "},
    ):
        response = client.put("/v1/users/me", headers=_h(seeded["member"]), json=body)
        assert response.status_code == 200, response.text

    assert _name_notices(client, seeded["trainer"]) == []


def test_already_received_notices_keep_the_old_name(client, seeded, db_session):
    """이미 받은 알림은 그때 이름으로 남는다 — 받은 순간의 기록이라 고쳐 쓰지 않는다."""
    old_body = f"{seeded['original']} 회원이 건강 목표를 바꿨어요: 체중 감량"
    trainer_id = db_session.scalar(
        select(User.id).where(User.email == "trainer@oncare.com")
    )
    old_id = f"noti-rename-{uuid4().hex[:8]}"
    db_session.add(
        Notification(
            id=old_id,
            user_id=trainer_id,
            title="회원 건강 목표 변경",
            body=old_body,
            category=notification_service.TRAINER_HEALTH_GOAL_KIND,
            subject_id=MEMBER_ID,
            read=False,
        )
    )
    db_session.commit()
    try:
        response = client.put(
            "/v1/users/me", headers=_h(seeded["member"]), json={"name": "이수진"}
        )
        assert response.status_code == 200, response.text

        inbox = client.get(
            "/v1/trainer/notifications", headers=_h(seeded["trainer"])
        ).json()
        kept = next(n for n in inbox if n["id"] == old_id)
        assert kept["body"] == old_body
    finally:
        db_session.execute(delete(Notification).where(Notification.id == old_id))
        db_session.commit()


def test_a_member_without_a_trainer_is_not_announced(client, db_session):
    """담당 트레이너가 없으면 알릴 사람이 없다. 이름은 그대로 바뀐다."""
    email = f"rename-{uuid4().hex[:10]}@oncare.com"
    registered = client.post(
        "/v1/auth/register",
        json={"email": email, "password": "rename-pw-123", "name": "처음이름"},
    )
    assert registered.status_code == 201, registered.text
    member_id = registered.json()["id"]
    token = _login(client, email, "rename-pw-123")

    response = client.put("/v1/users/me", headers=_h(token), json={"name": "새이름"})

    assert response.status_code == 200, response.text
    db_session.expire_all()
    assert db_session.get(User, member_id).name == "새이름"
    assert (
        db_session.scalar(
            select(Notification.id).where(
                Notification.category
                == notification_service.TRAINER_MEMBER_NAME_KIND,
                Notification.subject_id == member_id,
            )
        )
        is None
    )


def test_renaming_during_onboarding_is_announced_too(client, seeded):
    """첫 설정에서도 이름을 고칠 수 있다 — 담당 트레이너가 있으면 같은 알림이다."""
    response = client.post(
        "/v1/users/me/onboarding",
        headers=_h(seeded["member"]),
        json={"name": "이수진"},
    )
    assert response.status_code == 200, response.text

    notices = _name_notices(client, seeded["trainer"])
    assert [n["body"] for n in notices] == [
        f"{seeded['original']} 회원이 이름을 바꿨어요: 이수진"
    ]
