"""담당이 생길 때 그 회원의 대기 중 담당 요청 정리. (#2894)

담당이 생기는 두 경로(동기화 코드 연결·담당 요청 수락)가 같은 트랜잭션 안에서
그 회원에게 걸린 대기 요청을 닫는다.

  * 연결된 트레이너가 보낸 대기 요청 → `accepted`(코드 연결이면 이력 행이 하나만)
  * 다른 트레이너가 보낸 대기 요청 → `cancelled`
  * 연결이 실패하면 대기 요청은 그대로

DB 가 필요하므로 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
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
from app.services import (
    consultation_service,
    notification_service,
    trainer_client_invite_service,
)

EMAIL_PREFIX = "invclean-test-"
PLACE_PREFIX = "invclean-place-"
PASSWORD = "invclean-pw-1234"


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


def _member(client) -> tuple[str, str]:
    """회원 하나. (id, token)"""
    email = f"{EMAIL_PREFIX}member-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={
            "email": email,
            "password": PASSWORD,
            "name": "정리 회원",
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
        name="정리 테스트 헬스장",
        category="fitness",
        address="서울",
    )
    db_session.add(place)
    trainer = User(
        id=f"invclean-trainer-{suffix}",
        email=email,
        name="정리 테스트 트레이너",
        hashed_password=hash_password(PASSWORD),
        role="trainer",
        is_active=True,
    )
    db_session.add(trainer)
    db_session.flush()
    db_session.add(TrainerProfile(trainer_id=trainer.id, gym_id=place.id))
    db_session.commit()
    return trainer.id, _login(client, email)


def _invite(client, trainer_token: str, member_id: str) -> str:
    response = client.post(
        "/v1/trainer/client-invites",
        json={"member_id": member_id},
        headers=_auth(trainer_token),
    )
    assert response.status_code == 201, response.text
    return response.json()["id"]


def _issue(client, member_token: str) -> str:
    response = client.post(
        "/v1/users/me/pairing-code", headers=_auth(member_token)
    )
    assert response.status_code == 200, response.text
    return response.json()["code"]


def _redeem(client, trainer_token: str, code: str):
    return client.post(
        "/v1/trainer/pairing-code",
        json={"code": code},
        headers=_auth(trainer_token),
    )


def _accept(client, member_token: str, invite_id: str):
    return client.post(
        f"/v1/me/coach/invites/{invite_id}/accept",
        headers=_auth(member_token),
        json={"data_sharing_consent": True},
    )


def _status(db_session, invite_id: str) -> str:
    db_session.expire_all()
    return db_session.get(TrainerClientInvite, invite_id).status


def _sent_pending_member_ids(client, trainer_token: str) -> list[str]:
    response = client.get(
        "/v1/trainer/client-invites", headers=_auth(trainer_token)
    )
    assert response.status_code == 200, response.text
    return [row["member_id"] for row in response.json()]


def _inbox_ids(client, member_token: str) -> list[str]:
    response = client.get("/v1/me/coach/invites", headers=_auth(member_token))
    assert response.status_code == 200, response.text
    return [row["id"] for row in response.json()]


def _accepted_notices(db_session, trainer_id: str) -> int:
    db_session.expire_all()
    return (
        db_session.query(Notification)
        .filter(
            Notification.user_id == trainer_id,
            Notification.category
            == notification_service.TRAINER_INVITE_ACCEPTED_KIND,
        )
        .count()
    )


# ---------------------------------------------------------------------------
# 동기화 코드 연결
# ---------------------------------------------------------------------------


def test_redeem_turns_own_pending_invite_into_the_accepted_trail(
    client, db_session
):
    """같은 트레이너가 앞서 보낸 요청이 이력이 된다 — 수락 행이 둘 남지 않는다."""
    member_id, member_token = _member(client)
    trainer_id, trainer_token = _trainer(client, db_session)
    invite_id = _invite(client, trainer_token, member_id)

    assert _redeem(client, trainer_token, _issue(client, member_token)).status_code == 200

    assert _status(db_session, invite_id) == "accepted"
    rows = (
        db_session.query(TrainerClientInvite)
        .filter(
            TrainerClientInvite.trainer_id == trainer_id,
            TrainerClientInvite.member_id == member_id,
        )
        .all()
    )
    assert [row.id for row in rows] == [invite_id]
    assert rows[0].decided_at is not None


def test_redeem_without_a_prior_invite_still_leaves_a_trail(client, db_session):
    member_id, member_token = _member(client)
    trainer_id, trainer_token = _trainer(client, db_session)

    assert _redeem(client, trainer_token, _issue(client, member_token)).status_code == 200

    statuses = [
        row.status
        for row in db_session.query(TrainerClientInvite)
        .filter(
            TrainerClientInvite.trainer_id == trainer_id,
            TrainerClientInvite.member_id == member_id,
        )
        .all()
    ]
    assert statuses == ["accepted"]


def test_redeem_cancels_other_trainers_pending_invites(client, db_session):
    member_id, member_token = _member(client)
    _, linking_token = _trainer(client, db_session)
    _, other_token = _trainer(client, db_session)
    other_invite = _invite(client, other_token, member_id)

    assert _redeem(client, linking_token, _issue(client, member_token)).status_code == 200

    assert _status(db_session, other_invite) == "cancelled"
    # 보낸 트레이너의 대기 목록에서도 빠진다.
    assert member_id not in _sent_pending_member_ids(client, other_token)


def test_after_redeem_nothing_is_left_waiting_on_either_screen(
    client, db_session
):
    """트레이너 웹 '답 기다리는 요청'과 회원 앱 받은 요청이 함께 비워진다."""
    member_id, member_token = _member(client)
    _, linking_token = _trainer(client, db_session)
    _, other_token = _trainer(client, db_session)
    _invite(client, linking_token, member_id)
    _invite(client, other_token, member_id)
    assert len(_inbox_ids(client, member_token)) == 2

    assert _redeem(client, linking_token, _issue(client, member_token)).status_code == 200

    assert member_id not in _sent_pending_member_ids(client, linking_token)
    assert _inbox_ids(client, member_token) == []


def test_redeem_does_not_lead_to_a_second_accepted_notice(client, db_session):
    """예전에는 남은 요청을 회원이 눌러 수락 알림이 한 번 더 갔다."""
    member_id, member_token = _member(client)
    trainer_id, trainer_token = _trainer(client, db_session)
    invite_id = _invite(client, trainer_token, member_id)
    assert _redeem(client, trainer_token, _issue(client, member_token)).status_code == 200
    before = _accepted_notices(db_session, trainer_id)

    # 남은 요청이 없으니 수락할 것도 없다.
    assert _accept(client, member_token, invite_id).status_code == 409

    assert _accepted_notices(db_session, trainer_id) == before


def test_a_failed_redeem_keeps_pending_invites(client, db_session, monkeypatch):
    """정리는 연결과 같은 트랜잭션이다 — 연결이 실패하면 대기 요청은 그대로다."""
    member_id, member_token = _member(client)
    trainer_id, trainer_token = _trainer(client, db_session)
    _, other_token = _trainer(client, db_session)
    own_invite = _invite(client, trainer_token, member_id)
    other_invite = _invite(client, other_token, member_id)
    code = _issue(client, member_token)

    def boom(*_args, **_kwargs):
        raise RuntimeError("헬스장 연결 실패")

    monkeypatch.setattr(consultation_service, "link_member_gym", boom)

    with pytest.raises(RuntimeError):
        trainer_client_invite_service.redeem_pairing_code(
            db_session, trainer_id, code
        )

    assert _status(db_session, own_invite) == "pending"
    assert _status(db_session, other_invite) == "pending"
    assert (
        db_session.query(TrainerClient)
        .filter(
            TrainerClient.member_id == member_id,
            TrainerClient.active.is_(True),
        )
        .count()
        == 0
    )


def test_a_refused_redeem_leaves_invites_alone(client, db_session):
    """이미 다른 트레이너가 담당이면 연결이 거절된다 — 남의 요청을 닫지 않는다."""
    member_id, member_token = _member(client)
    _, first_token = _trainer(client, db_session)
    second_id, second_token = _trainer(client, db_session)
    assert _redeem(client, first_token, _issue(client, member_token)).status_code == 200
    # 담당이 생긴 뒤에는 API 로 요청을 보낼 수 없다 — 정리 이전에 남은 행처럼
    # 직접 넣는다.
    stale = TrainerClientInvite(
        id=f"tci-{uuid4().hex[:12]}",
        trainer_id=second_id,
        member_id=member_id,
        status="pending",
    )
    db_session.add(stale)
    db_session.commit()

    assert _redeem(client, second_token, _issue(client, member_token)).status_code == 409

    assert _status(db_session, stale.id) == "pending"


# ---------------------------------------------------------------------------
# 담당 요청 수락
# ---------------------------------------------------------------------------


def test_accept_cancels_the_other_trainers_pending_invites(client, db_session):
    member_id, member_token = _member(client)
    _, chosen_token = _trainer(client, db_session)
    _, other_token = _trainer(client, db_session)
    _, third_token = _trainer(client, db_session)
    chosen = _invite(client, chosen_token, member_id)
    other = _invite(client, other_token, member_id)
    third = _invite(client, third_token, member_id)

    assert _accept(client, member_token, chosen).status_code == 200

    assert _status(db_session, chosen) == "accepted"
    assert _status(db_session, other) == "cancelled"
    assert _status(db_session, third) == "cancelled"
    assert _inbox_ids(client, member_token) == []
    assert member_id not in _sent_pending_member_ids(client, other_token)


def test_accept_sends_exactly_one_accepted_notice(client, db_session):
    member_id, member_token = _member(client)
    trainer_id, trainer_token = _trainer(client, db_session)
    _, other_token = _trainer(client, db_session)
    invite_id = _invite(client, trainer_token, member_id)
    _invite(client, other_token, member_id)

    assert _accept(client, member_token, invite_id).status_code == 200

    assert _accepted_notices(db_session, trainer_id) == 1


def test_accept_does_not_touch_other_members_invites(client, db_session):
    member_id, member_token = _member(client)
    other_member_id, other_member_token = _member(client)
    _, trainer_token = _trainer(client, db_session)
    _, other_token = _trainer(client, db_session)
    mine = _invite(client, trainer_token, member_id)
    unrelated = _invite(client, other_token, other_member_id)

    assert _accept(client, member_token, mine).status_code == 200

    assert _status(db_session, unrelated) == "pending"
    assert _inbox_ids(client, other_member_token) == [unrelated]


# ---------------------------------------------------------------------------
# 정리 함수 단위
# ---------------------------------------------------------------------------


def test_close_pending_marks_own_accepted_and_others_cancelled(
    client, db_session
):
    member_id, _ = _member(client)
    own_id, own_token = _trainer(client, db_session)
    _, other_token = _trainer(client, db_session)
    own_invite = _invite(client, own_token, member_id)
    other_invite = _invite(client, other_token, member_id)

    returned = trainer_client_invite_service._close_pending_for_member(
        db_session, member_id, linked_trainer_id=own_id
    )
    db_session.commit()

    assert returned is not None and returned.id == own_invite
    assert _status(db_session, own_invite) == "accepted"
    assert _status(db_session, other_invite) == "cancelled"
    assert db_session.get(TrainerClientInvite, other_invite).decided_at is not None


def test_close_pending_skips_the_excluded_row(client, db_session):
    member_id, _ = _member(client)
    own_id, own_token = _trainer(client, db_session)
    own_invite = _invite(client, own_token, member_id)

    returned = trainer_client_invite_service._close_pending_for_member(
        db_session, member_id, linked_trainer_id=own_id, exclude_id=own_invite
    )
    db_session.commit()

    assert returned is None
    assert _status(db_session, own_invite) == "pending"


def test_close_pending_with_nothing_waiting_returns_none(client, db_session):
    member_id, _ = _member(client)
    own_id, _ = _trainer(client, db_session)

    assert (
        trainer_client_invite_service._close_pending_for_member(
            db_session, member_id, linked_trainer_id=own_id
        )
        is None
    )
