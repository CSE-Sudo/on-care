"""트레이너 안읽음 집계는 지금 담당 중인 회원만 센다. (#2868)

회원이 메시지를 보낸 뒤 트레이너가 읽기 전에 담당이 끊기거나 동의가 철회되면,
`GET /trainer/chat/unread` 가 그 회원의 안읽음을 계속 돌려줬다. 읽음 처리는
`_require_client` 로 살아 있는 담당을 요구해 404 라, 트레이너 웹 배지가 지울 수
없는 숫자로 굳었다.

여기서 보는 것:

* 규칙(`data_consent_service.link_is_open` / `open_link_clause`) — DB 없이.
* 담당 해제(트레이너·회원 어느 쪽이든)·동의 철회 회원의 안읽음은 응답에서 빠진다.
* 빠진 모양이 남의 회원과 같다(키 없음) — 예전 담당 사실이 드러나지 않는다.
* 메시지 행은 그대로라, 코드로 다시 연결(새 동의)하면 남은 안읽음이 다시 보인다.
* 담당 중인 회원의 안읽음은 그대로 센다.
"""

from __future__ import annotations

from datetime import timedelta
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core import clock
from app.core.security import hash_password
from app.models.models import (
    ChatMessage,
    MemberPairingCode,
    Notification,
    Place,
    TrainerClient,
    TrainerClientInvite,
    TrainerProfile,
    User,
)
from app.services import data_consent_service

EMAIL_PREFIX = "unread2868-"
PLACE_PREFIX = "unread2868-place-"
PASSWORD = "unread-pw-1234"


# ---------------------------------------------------------------------------
# 규칙 — DB 없이
# ---------------------------------------------------------------------------


def _link(**kwargs) -> TrainerClient:
    fields = {"id": "tc-unit", "trainer_id": "t", "member_id": "m", "active": True}
    fields.update(kwargs)
    return TrainerClient(**fields)


def test_a_live_consented_link_is_open():
    assert data_consent_service.link_is_open(_link(data_consent_at=clock.now()))


def test_a_link_from_before_consent_existed_is_open():
    # 동의 기능 이전 링크(동의도 철회도 없음)는 막지 않는다 — blocks_access 와 같은 규칙.
    assert data_consent_service.link_is_open(_link())


def test_a_released_link_is_not_open():
    assert not data_consent_service.link_is_open(
        _link(active=False, data_consent_at=clock.now())
    )


def test_a_revoked_link_is_not_open_even_if_active():
    assert not data_consent_service.link_is_open(
        _link(data_consent_at=None, data_consent_revoked_at=clock.now())
    )


def test_a_revived_link_with_new_consent_is_open():
    revoked = clock.now() - timedelta(days=1)
    assert data_consent_service.link_is_open(
        _link(data_consent_at=clock.now(), data_consent_revoked_at=revoked)
    )


def test_no_link_is_not_open():
    assert not data_consent_service.link_is_open(None)


def test_open_clause_names_active_and_both_consent_columns():
    compiled = str(data_consent_service.open_link_clause())
    assert "active" in compiled
    assert "data_consent_at IS NOT NULL" in compiled
    assert "data_consent_revoked_at IS NULL" in compiled


# ---------------------------------------------------------------------------
# DB 픽스처
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _cleanup(request):
    if "db_session" not in request.fixturenames:
        yield
        return
    db_session = request.getfixturevalue("db_session")
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
        db_session.query(ChatMessage).filter(
            (ChatMessage.trainer_id.in_(user_ids))
            | (ChatMessage.member_id.in_(user_ids))
        ).delete(synchronize_session=False)
        db_session.query(Notification).filter(
            Notification.user_id.in_(user_ids)
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


def _member(client) -> tuple[str, str]:
    email = f"{EMAIL_PREFIX}member-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={
            "email": email,
            "password": PASSWORD,
            "name": "안읽음 확인 회원",
            "phone": "010-1234-5678",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["id"], _login(client, email)


def _trainer(client, db_session) -> tuple[str, str]:
    suffix = uuid4().hex[:10]
    email = f"{EMAIL_PREFIX}trainer-{suffix}@oncare.com"
    place = Place(
        id=f"{PLACE_PREFIX}{suffix}",
        name="안읽음 확인 헬스장",
        category="fitness",
        address="서울",
    )
    db_session.add(place)
    trainer = User(
        id=f"unread2868-trainer-{suffix}",
        email=email,
        name="안읽음 확인 트레이너",
        hashed_password=hash_password(PASSWORD),
        role="trainer",
        is_active=True,
    )
    db_session.add(trainer)
    db_session.flush()
    db_session.add(TrainerProfile(trainer_id=trainer.id, gym_id=place.id))
    db_session.commit()
    return trainer.id, _login(client, email)


def _pair_by_code(client, member_token: str, trainer_token: str) -> None:
    issued = client.post("/v1/users/me/pairing-code", headers=_auth(member_token))
    assert issued.status_code == 200, issued.text
    redeemed = client.post(
        "/v1/trainer/pairing-code",
        json={"code": issued.json()["code"]},
        headers=_auth(trainer_token),
    )
    assert redeemed.status_code == 200, redeemed.text


def _member_says(db_session, trainer_id: str, member_id: str, n: int = 1) -> None:
    for _ in range(n):
        db_session.add(
            ChatMessage(
                id=f"unread2868-{uuid4().hex[:12]}",
                trainer_id=trainer_id,
                member_id=member_id,
                sender="member",
                body="확인 부탁드려요",
                created_at=clock.now(),
            )
        )
    db_session.commit()


def _unread(client, trainer_token: str) -> dict[str, int]:
    response = client.get("/v1/trainer/chat/unread", headers=_auth(trainer_token))
    assert response.status_code == 200, response.text
    return response.json()


def _link_of(db_session, trainer_id: str, member_id: str) -> TrainerClient:
    db_session.expire_all()
    return db_session.scalars(
        select(TrainerClient).where(
            TrainerClient.trainer_id == trainer_id,
            TrainerClient.member_id == member_id,
        )
    ).one()


def _linked_with_unread(client, db_session, n: int = 2):
    member_id, member_token = _member(client)
    trainer_id, trainer_token = _trainer(client, db_session)
    _pair_by_code(client, member_token, trainer_token)
    _member_says(db_session, trainer_id, member_id, n)
    assert _unread(client, trainer_token).get(member_id) == n
    return member_id, member_token, trainer_id, trainer_token


# ---------------------------------------------------------------------------
# 집계 범위
# ---------------------------------------------------------------------------


def test_trainer_release_drops_the_member_from_unread(client, db_session):
    member_id, _, _, trainer_token = _linked_with_unread(client, db_session)

    response = client.delete(
        f"/v1/trainer/clients/{member_id}", headers=_auth(trainer_token)
    )
    assert response.status_code == 204, response.text

    assert member_id not in _unread(client, trainer_token)


def test_member_disconnect_drops_the_member_from_unread(client, db_session):
    member_id, member_token, _, trainer_token = _linked_with_unread(client, db_session)

    response = client.delete("/v1/me/coach/trainer", headers=_auth(member_token))
    assert response.status_code == 204, response.text

    assert member_id not in _unread(client, trainer_token)


def test_revoked_consent_on_a_live_link_drops_the_member(client, db_session):
    member_id, _, trainer_id, trainer_token = _linked_with_unread(client, db_session)
    link = _link_of(db_session, trainer_id, member_id)
    data_consent_service.revoke(link)
    db_session.commit()
    assert _link_of(db_session, trainer_id, member_id).active is True

    assert member_id not in _unread(client, trainer_token)


def test_released_member_looks_the_same_as_someone_elses_member(client, db_session):
    member_id, _, _, trainer_token = _linked_with_unread(client, db_session)
    # 남의 회원: 다른 트레이너에게 메시지를 보낸 회원은 처음부터 키가 없다.
    other_member, other_token = _member(client)
    other_trainer, other_trainer_token = _trainer(client, db_session)
    _pair_by_code(client, other_token, other_trainer_token)
    _member_says(db_session, other_trainer, other_member)

    assert (
        client.delete(
            f"/v1/trainer/clients/{member_id}", headers=_auth(trainer_token)
        ).status_code
        == 204
    )

    unread = _unread(client, trainer_token)
    assert member_id not in unread
    assert other_member not in unread
    # 0 으로라도 남기면 "예전 회원" 이 키로 드러난다.
    assert unread == {}


def test_release_keeps_the_rows_unread(client, db_session):
    """정책 (a): 집계에서만 빼고 행은 그대로 둔다."""
    member_id, _, trainer_id, trainer_token = _linked_with_unread(
        client, db_session, n=3
    )
    assert (
        client.delete(
            f"/v1/trainer/clients/{member_id}", headers=_auth(trainer_token)
        ).status_code
        == 204
    )

    db_session.expire_all()
    still_unread = db_session.scalars(
        select(ChatMessage).where(
            ChatMessage.trainer_id == trainer_id,
            ChatMessage.member_id == member_id,
            ChatMessage.read_at.is_(None),
        )
    ).all()
    assert len(still_unread) == 3


def test_reconnecting_by_code_brings_the_unread_back(client, db_session):
    member_id, member_token, _, trainer_token = _linked_with_unread(
        client, db_session, n=2
    )
    assert (
        client.delete("/v1/me/coach/trainer", headers=_auth(member_token)).status_code
        == 204
    )
    assert member_id not in _unread(client, trainer_token)

    _pair_by_code(client, member_token, trainer_token)

    assert _unread(client, trainer_token).get(member_id) == 2


def test_trainer_alone_cannot_bring_the_unread_back(client, db_session):
    member_id, _, _, trainer_token = _linked_with_unread(client, db_session)
    assert (
        client.delete(
            f"/v1/trainer/clients/{member_id}", headers=_auth(trainer_token)
        ).status_code
        == 204
    )

    restored = client.put(
        f"/v1/trainer/clients/{member_id}/registration", headers=_auth(trainer_token)
    )

    assert restored.status_code == 409, restored.text
    assert member_id not in _unread(client, trainer_token)


def test_counted_members_are_exactly_the_ones_that_can_be_marked_read(
    client, db_session
):
    """집계에 나오는 회원은 읽음 처리가 되고, 안 나오는 회원은 404 — 비대칭이 없다."""
    kept_id, kept_token = _member(client)
    gone_id, gone_token = _member(client)
    trainer_id, trainer_token = _trainer(client, db_session)
    _pair_by_code(client, kept_token, trainer_token)
    _pair_by_code(client, gone_token, trainer_token)
    _member_says(db_session, trainer_id, kept_id)
    _member_says(db_session, trainer_id, gone_id)
    assert (
        client.delete("/v1/me/coach/trainer", headers=_auth(gone_token)).status_code
        == 204
    )

    unread = _unread(client, trainer_token)
    assert set(unread) == {kept_id}

    kept_read = client.post(
        f"/v1/trainer/clients/{kept_id}/chat/read", headers=_auth(trainer_token)
    )
    gone_read = client.post(
        f"/v1/trainer/clients/{gone_id}/chat/read", headers=_auth(trainer_token)
    )
    assert kept_read.status_code == 200, kept_read.text
    assert gone_read.status_code == 404, gone_read.text
    assert _unread(client, trainer_token).get(kept_id, 0) == 0


def test_active_member_unread_is_still_counted(client, db_session):
    member_id, _, _, trainer_token = _linked_with_unread(client, db_session, n=4)
    assert _unread(client, trainer_token)[member_id] == 4
