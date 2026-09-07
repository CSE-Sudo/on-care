"""트레이너 → 회원 담당 요청과 회원의 수락. (#919)

담당 관계가 생기는 **두 번째 경로**다. 첫 경로(상담 수락)와 다른 점은 방향뿐이고,
지켜야 할 불변식은 같다 — 회원당 활성 담당은 1명, 휴면 링크는 되살린다.

여기서 가장 중요하게 보는 것은 "트레이너가 요청을 보낸 것만으로는 명단에 아무것도
생기지 않는다" 이다. 담당은 상대의 식단·건강 기록을 여는 권한이라, 한쪽이
일방적으로 만들 수 있으면 그 권한이 동의 없이 열린다.

DB 가 필요하므로 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest

from app.core.security import hash_password
from app.models.models import (
    MemberGym,
    Notification,
    Place,
    TrainerClient,
    TrainerClientInvite,
    TrainerProfile,
    User,
)

EMAIL_PREFIX = "invite-test-"
PLACE_PREFIX = "invite-place-"
PASSWORD = "invite-pw-1234"


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
    db_session.query(MemberGym).filter(
        MemberGym.gym_id.like(f"{PLACE_PREFIX}%")
    ).delete(synchronize_session=False)
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


def _member(client, name: str = "초대 회원") -> tuple[str, str, str]:
    """회원 계정 하나. (id, email, token)"""
    email = f"{EMAIL_PREFIX}member-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": name},
    )
    assert response.status_code == 201, response.text
    return response.json()["id"], email, _login(client, email)


def _gym(db_session) -> Place:
    place = Place(
        id=f"{PLACE_PREFIX}{uuid4().hex[:10]}",
        name="초대 테스트 헬스장",
        category="fitness",
        address="서울",
    )
    db_session.add(place)
    db_session.commit()
    return place


def _trainer(client, db_session) -> tuple[User, str]:
    suffix = uuid4().hex[:10]
    email = f"{EMAIL_PREFIX}trainer-{suffix}@oncare.com"
    trainer = User(
        id=f"invite-trainer-{suffix}",
        email=email,
        name="초대 테스트 트레이너",
        hashed_password=hash_password(PASSWORD),
        role="trainer",
        is_active=True,
    )
    db_session.add(trainer)
    db_session.flush()
    db_session.add(
        TrainerProfile(trainer_id=trainer.id, gym_id=_gym(db_session).id)
    )
    db_session.commit()
    return trainer, _login(client, email)


def _invite(client, trainer_token: str, member_id: str, message: str | None = None) -> str:
    response = client.post(
        "/v1/trainer/client-invites",
        json={"member_id": member_id, "message": message},
        headers=_auth(trainer_token),
    )
    assert response.status_code == 201, response.text
    return response.json()["id"]


def _roster_ids(client, trainer_token: str) -> list[str]:
    response = client.get("/v1/trainer/clients", headers=_auth(trainer_token))
    assert response.status_code == 200, response.text
    return [row["id"] for row in response.json()]


def test_inviting_does_not_touch_the_roster(client, db_session):
    """요청을 보낸 것만으로는 담당이 생기지 않는다 — 이 테스트가 이 기능의 요지다."""
    _, trainer_token = _trainer(client, db_session)
    member_id, _, _ = _member(client)

    _invite(client, trainer_token, member_id, "센터에서 뵀던 담당입니다.")

    assert member_id not in _roster_ids(client, trainer_token)
    assert (
        db_session.query(TrainerClient)
        .filter(TrainerClient.member_id == member_id)
        .count()
        == 0
    )


def test_the_member_sees_the_invite_and_gets_a_notification(client, db_session):
    trainer, trainer_token = _trainer(client, db_session)
    member_id, _, member_token = _member(client)

    invite_id = _invite(client, trainer_token, member_id, "함께 해요")

    response = client.get("/v1/me/coach/invites", headers=_auth(member_token))
    assert response.status_code == 200, response.text
    rows = response.json()
    assert [row["id"] for row in rows] == [invite_id]
    assert rows[0]["trainer_name"] == trainer.name
    assert rows[0]["message"] == "함께 해요"

    # 알림이 없으면 회원은 요청이 왔다는 사실 자체를 알 수 없다.
    assert (
        db_session.query(Notification)
        .filter(
            Notification.user_id == member_id,
            Notification.title == "담당 요청이 도착했어요",
        )
        .count()
        == 1
    )


def test_accepting_creates_the_link_and_the_roster_row(client, db_session):
    trainer, trainer_token = _trainer(client, db_session)
    member_id, _, member_token = _member(client)
    invite_id = _invite(client, trainer_token, member_id)

    response = client.post(
        f"/v1/me/coach/invites/{invite_id}/accept", headers=_auth(member_token),
        json={"data_sharing_consent": True},
    )

    assert response.status_code == 200, response.text
    assert response.json()["status"] == "accepted"
    assert member_id in _roster_ids(client, trainer_token)

    # 회원 쪽에서도 담당이 보인다 — 링크가 진짜로 생겼다는 뜻.
    coach = client.get("/v1/me/coach", headers=_auth(member_token))
    assert coach.status_code == 200, coach.text
    assert coach.json()["trainer_id"] == trainer.id


def test_accepting_links_the_member_to_the_trainer_gym(client, db_session):
    trainer, trainer_token = _trainer(client, db_session)
    member_id, _, member_token = _member(client)
    invite_id = _invite(client, trainer_token, member_id)

    client.post(
        f"/v1/me/coach/invites/{invite_id}/accept", headers=_auth(member_token),
        json={"data_sharing_consent": True},
    )

    gym_id = (
        db_session.query(TrainerProfile.gym_id)
        .filter(TrainerProfile.trainer_id == trainer.id)
        .scalar()
    )
    assert db_session.get(MemberGym, member_id).gym_id == gym_id


def test_rejecting_leaves_the_roster_alone(client, db_session):
    _, trainer_token = _trainer(client, db_session)
    member_id, _, member_token = _member(client)
    invite_id = _invite(client, trainer_token, member_id)

    response = client.post(
        f"/v1/me/coach/invites/{invite_id}/reject", headers=_auth(member_token)
    )

    assert response.status_code == 200, response.text
    assert response.json()["status"] == "rejected"
    assert member_id not in _roster_ids(client, trainer_token)
    assert client.get("/v1/me/coach/invites", headers=_auth(member_token)).json() == []


def test_a_decided_invite_cannot_be_decided_again(client, db_session):
    _, trainer_token = _trainer(client, db_session)
    member_id, _, member_token = _member(client)
    invite_id = _invite(client, trainer_token, member_id)
    client.post(
        f"/v1/me/coach/invites/{invite_id}/accept", headers=_auth(member_token),
        json={"data_sharing_consent": True},
    )

    again = client.post(
        f"/v1/me/coach/invites/{invite_id}/reject", headers=_auth(member_token)
    )

    assert again.status_code == 409


def test_a_second_pending_invite_to_the_same_member_is_refused(client, db_session):
    _, trainer_token = _trainer(client, db_session)
    member_id, _, _ = _member(client)
    _invite(client, trainer_token, member_id)

    response = client.post(
        "/v1/trainer/client-invites",
        json={"member_id": member_id},
        headers=_auth(trainer_token),
    )

    assert response.status_code == 409


def test_a_member_who_already_has_a_trainer_cannot_be_invited(client, db_session):
    first, first_token = _trainer(client, db_session)
    _, second_token = _trainer(client, db_session)
    member_id, _, member_token = _member(client)
    invite_id = _invite(client, first_token, member_id)
    client.post(
        f"/v1/me/coach/invites/{invite_id}/accept", headers=_auth(member_token),
        json={"data_sharing_consent": True},
    )

    response = client.post(
        "/v1/trainer/client-invites",
        json={"member_id": member_id},
        headers=_auth(second_token),
    )

    assert response.status_code == 409
    assert first.id  # 담당은 그대로 첫 트레이너다
    coach = client.get("/v1/me/coach", headers=_auth(member_token))
    assert coach.json()["trainer_id"] == first.id


def test_an_invite_accepted_after_another_trainer_took_the_member_is_refused(
    client, db_session
):
    """보낼 때는 비어 있었지만 수락하는 사이에 담당이 생긴 경우.

    회원당 활성 담당 1명이라는 불변식을 IntegrityError 로 만나기 전에 막는다.
    """
    _, first_token = _trainer(client, db_session)
    _, second_token = _trainer(client, db_session)
    member_id, _, member_token = _member(client)
    stale_invite = _invite(client, first_token, member_id)
    other_invite = _invite(client, second_token, member_id)
    client.post(
        f"/v1/me/coach/invites/{other_invite}/accept", headers=_auth(member_token),
        json={"data_sharing_consent": True},
    )

    response = client.post(
        f"/v1/me/coach/invites/{stale_invite}/accept", headers=_auth(member_token),
        json={"data_sharing_consent": True},
    )

    assert response.status_code == 409


def test_a_cancelled_invite_disappears_from_the_member_inbox(client, db_session):
    _, trainer_token = _trainer(client, db_session)
    member_id, _, member_token = _member(client)
    invite_id = _invite(client, trainer_token, member_id)

    cancelled = client.delete(
        f"/v1/trainer/client-invites/{invite_id}", headers=_auth(trainer_token)
    )

    assert cancelled.status_code == 200, cancelled.text
    assert client.get("/v1/me/coach/invites", headers=_auth(member_token)).json() == []


def test_another_trainers_invite_cannot_be_cancelled(client, db_session):
    _, owner_token = _trainer(client, db_session)
    _, stranger_token = _trainer(client, db_session)
    member_id, _, _ = _member(client)
    invite_id = _invite(client, owner_token, member_id)

    response = client.delete(
        f"/v1/trainer/client-invites/{invite_id}", headers=_auth(stranger_token)
    )

    # 남의 요청은 존재조차 드러내지 않는다.
    assert response.status_code == 404


def test_a_member_cannot_decide_someone_elses_invite(client, db_session):
    _, trainer_token = _trainer(client, db_session)
    member_id, _, _ = _member(client)
    _, _, stranger_token = _member(client)
    invite_id = _invite(client, trainer_token, member_id)

    response = client.post(
        f"/v1/me/coach/invites/{invite_id}/accept", headers=_auth(stranger_token),
        json={"data_sharing_consent": True},
    )

    assert response.status_code == 404


def test_a_trainer_account_cannot_be_invited(client, db_session):
    _, trainer_token = _trainer(client, db_session)
    other, _ = _trainer(client, db_session)

    response = client.post(
        "/v1/trainer/client-invites",
        json={"member_id": other.id},
        headers=_auth(trainer_token),
    )

    assert response.status_code == 422


def test_the_sent_list_shows_what_happened(client, db_session):
    _, trainer_token = _trainer(client, db_session)
    member_id, _, member_token = _member(client, name="정수락")
    invite_id = _invite(client, trainer_token, member_id)
    client.post(
        f"/v1/me/coach/invites/{invite_id}/accept", headers=_auth(member_token),
        json={"data_sharing_consent": True},
    )

    pending = client.get(
        "/v1/trainer/client-invites", headers=_auth(trainer_token)
    )
    assert pending.json() == []

    everything = client.get(
        "/v1/trainer/client-invites",
        params={"status": "all"},
        headers=_auth(trainer_token),
    )
    rows = everything.json()
    assert [(row["member_name"], row["status"]) for row in rows] == [
        ("정수락", "accepted")
    ]
