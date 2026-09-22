"""담당 회원이 떠나면 트레이너 알림함에 남긴다. (#2174) DB 필요.

회원이 탈퇴하거나 담당 트레이너·헬스장 연결을 끊으면 트레이너 회원 목록에서 바로
사라진다. 여기서 보는 것:

  * 세 경로(탈퇴·트레이너만 해제·헬스장 해제) 모두 담당 트레이너에게 한 건씩 남는다.
  * 탈퇴 알림은 회원 계정이 지워진 뒤에도 남는다(트레이너 계정에 달린다).
  * 담당이 없던 회원이 끊거나 두 번 끊으면 알림이 생기지 않는다.

담당 관계는 동기화 코드(#1634)로 만든다 — 회원 동의가 먼저 오는 경로라 준비가 가장 짧다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest

from app.core.security import hash_password
from app.models.models import (
    MemberGym,
    MemberPairingCode,
    Notification,
    Place,
    TrainerClient,
    TrainerClientInvite,
    TrainerProfile,
    User,
)
from app.services.notification_service import TRAINER_MEMBER_LEFT_KIND

EMAIL_PREFIX = "departure-test-"
PLACE_PREFIX = "departure-place-"
PASSWORD = "departure-pw-1234"


@pytest.fixture(autouse=True)
def _cleanup(db_session):
    yield
    db_session.rollback()
    user_ids = [
        row[0]
        for row in db_session.query(User.id)
        .filter(User.email.like(f"{EMAIL_PREFIX}%"))
        .all()
    ]
    if user_ids:
        db_session.query(MemberPairingCode).filter(
            MemberPairingCode.member_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(TrainerClientInvite).filter(
            (TrainerClientInvite.trainer_id.in_(user_ids))
            | (TrainerClientInvite.member_id.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(TrainerClient).filter(
            (TrainerClient.trainer_id.in_(user_ids))
            | (TrainerClient.member_id.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(Notification).filter(
            Notification.user_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(MemberGym).filter(
            MemberGym.member_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(TrainerProfile).filter(
            TrainerProfile.trainer_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(User).filter(User.id.in_(user_ids)).delete(
            synchronize_session=False
        )
    db_session.query(Place).filter(Place.id.like(f"{PLACE_PREFIX}%")).delete(
        synchronize_session=False
    )
    db_session.commit()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _login(client, email: str) -> str:
    response = client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _member(client, name: str) -> tuple[str, str]:
    """회원 하나. (id, token)"""
    email = f"{EMAIL_PREFIX}member-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={
            "email": email,
            "password": PASSWORD,
            "name": name,
            "phone": "010-1234-5678",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["id"], _login(client, email)


def _trainer(client, db_session) -> tuple[str, str]:
    """트레이너 하나. (id, token)"""
    suffix = uuid4().hex[:10]
    email = f"{EMAIL_PREFIX}trainer-{suffix}@oncare.com"
    place = Place(
        id=f"{PLACE_PREFIX}{suffix}",
        name="떠남 테스트 헬스장",
        category="fitness",
        address="서울",
    )
    db_session.add(place)
    trainer = User(
        id=f"departure-trainer-{suffix}",
        email=email,
        name="떠남 테스트 트레이너",
        hashed_password=hash_password(PASSWORD),
        role="trainer",
        is_active=True,
    )
    db_session.add(trainer)
    db_session.flush()
    db_session.add(TrainerProfile(trainer_id=trainer.id, gym_id=place.id))
    db_session.commit()
    return trainer.id, _login(client, email)


def _link(client, member_token: str, trainer_token: str) -> None:
    """동기화 코드로 담당을 만든다."""
    issued = client.post("/v1/users/me/pairing-code", headers=_auth(member_token))
    assert issued.status_code == 200, issued.text
    redeemed = client.post(
        "/v1/trainer/pairing-code",
        json={"code": issued.json()["code"]},
        headers=_auth(trainer_token),
    )
    assert redeemed.status_code == 200, redeemed.text


def _left_notifications(client, trainer_token: str) -> list[dict]:
    response = client.get("/v1/trainer/notifications", headers=_auth(trainer_token))
    assert response.status_code == 200, response.text
    return [
        row for row in response.json() if row["category"] == TRAINER_MEMBER_LEFT_KIND
    ]


def test_withdrawal_leaves_a_notice_that_outlives_the_member(client, db_session):
    """회원 행이 지워져도 알림은 트레이너 계정에 남는다."""
    member_id, member_token = _member(client, name="탈퇴회원")
    _, trainer_token = _trainer(client, db_session)
    _link(client, member_token, trainer_token)

    response = client.delete("/v1/users/me", headers=_auth(member_token))

    assert response.status_code == 200, response.text
    assert db_session.get(User, member_id) is None
    rows = _left_notifications(client, trainer_token)
    assert len(rows) == 1
    assert rows[0]["title"] == "회원 탈퇴"
    assert "탈퇴회원" in rows[0]["body"]
    assert rows[0]["read"] is False
    # 떠난 회원의 상세는 열 수 없어 가리킬 회원을 남기지 않는다.
    assert rows[0].get("subject_id") in (None, "")


@pytest.mark.parametrize("path", ["/v1/me/coach/trainer", "/v1/me/coach"])
def test_disconnecting_tells_the_trainer(client, db_session, path):
    """트레이너만 끊든 헬스장째 끊든 담당은 끝난다 — 둘 다 알린다."""
    _, member_token = _member(client, name="해제회원")
    _, trainer_token = _trainer(client, db_session)
    _link(client, member_token, trainer_token)

    response = client.delete(path, headers=_auth(member_token))

    assert response.status_code == 204, response.text
    rows = _left_notifications(client, trainer_token)
    assert len(rows) == 1
    assert rows[0]["title"] == "담당 연결 해제"
    assert "해제회원" in rows[0]["body"]


def test_disconnecting_twice_notifies_once(client, db_session):
    """해제는 멱등이다 — 이미 끊긴 뒤의 해제는 알릴 트레이너가 없다."""
    _, member_token = _member(client, name="두번해제")
    _, trainer_token = _trainer(client, db_session)
    _link(client, member_token, trainer_token)

    for _ in range(2):
        response = client.delete("/v1/me/coach/trainer", headers=_auth(member_token))
        assert response.status_code == 204, response.text

    assert len(_left_notifications(client, trainer_token)) == 1


def test_a_member_without_a_trainer_leaves_no_notice(client, db_session):
    """담당이 없던 회원의 탈퇴는 누구에게도 알림을 만들지 않는다."""
    _, member_token = _member(client, name="혼자회원")
    before = db_session.query(Notification).filter(
        Notification.category == TRAINER_MEMBER_LEFT_KIND
    ).count()

    response = client.delete("/v1/users/me", headers=_auth(member_token))

    assert response.status_code == 200, response.text
    db_session.expire_all()
    after = db_session.query(Notification).filter(
        Notification.category == TRAINER_MEMBER_LEFT_KIND
    ).count()
    assert after == before
