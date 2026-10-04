"""담당 해제 = 데이터 공유 동의 철회. (#1631)

담당을 끊어도 `data_consent_at` 이 남아, 같은 트레이너와 다시 이어지면 새 동의
없이 옛 동의가 되살아났다. 철회했다는 사실도 남지 않았다.

여기서 보는 것:

* 규칙 자체(`data_consent_service`) — DB 없이.
* 링크가 끊기는 경로마다(회원의 트레이너 해제·헬스장 해제, 트레이너의 해제,
  다른 트레이너로 옮김, 계정 탈퇴) 동의가 비고 철회 시각이 남는다.
* 되살릴 때는 그 연결의 새 동의만 적힌다. 새 동의가 없으면 트레이너는 회원
  기록을 열 수 없다(남의 회원과 같은 404).
* 트레이너 혼자 재등록해 동의를 되살릴 수 없다(409).
* 이미 주고받은 채팅·리포트는 지워지지 않는다.
* 회원 메모는 출처와 상관없이 남고, 새 동의로 다시 이어져야 다시 보인다(#2520).
* 마이그레이션이 이미 끊긴 링크의 옛 동의를 비운다.
"""
from __future__ import annotations

import importlib
from datetime import datetime, timedelta
from uuid import uuid4

import pytest
import sqlalchemy as sa
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import inspect, select

from app.core import clock
from app.core.security import hash_password
from app.models.models import (
    ChatMessage,
    MemberGym,
    MemberPairingCode,
    Notification,
    Place,
    TrainerClient,
    TrainerClientInvite,
    TrainerClientMemo,
    TrainerProfile,
    TrainerReportFeedback,
    User,
)
from app.services import consultation_service, data_consent_service

EMAIL_PREFIX = "consent1631-"
PLACE_PREFIX = "consent1631-place-"
PASSWORD = "consent-pw-1234"
GUARD_DETAIL = "담당 회원을 찾을 수 없습니다."


# ---------------------------------------------------------------------------
# 규칙 — DB 없이
# ---------------------------------------------------------------------------


def _link(**kwargs) -> TrainerClient:
    return TrainerClient(
        id="tc-unit", trainer_id="t", member_id="m", active=True, **kwargs
    )


def test_revoke_clears_consent_and_records_when():
    consented = clock.now() - timedelta(days=30)
    link = _link(data_consent_at=consented)
    at = clock.now()

    data_consent_service.revoke(link, at=at)

    assert link.data_consent_at is None
    assert link.data_consent_revoked_at == at
    assert data_consent_service.blocks_access(link)


def test_revoke_defaults_to_now():
    link = _link(data_consent_at=clock.now() - timedelta(days=1))
    before = clock.now()

    data_consent_service.revoke(link)

    assert link.data_consent_revoked_at is not None
    assert link.data_consent_revoked_at >= before


def test_revoking_twice_keeps_the_first_revocation_time():
    link = _link(data_consent_at=clock.now() - timedelta(days=3))
    first = clock.now() - timedelta(hours=2)
    data_consent_service.revoke(link, at=first)

    data_consent_service.revoke(link, at=clock.now())

    assert link.data_consent_revoked_at == first


def test_revoking_after_a_new_consent_moves_the_revocation_time():
    link = _link(data_consent_at=None, data_consent_revoked_at=clock.now() - timedelta(days=5))
    data_consent_service.grant(link, clock.now() - timedelta(days=1))
    later = clock.now()

    data_consent_service.revoke(link, at=later)

    assert link.data_consent_at is None
    assert link.data_consent_revoked_at == later


def test_revoking_a_legacy_link_without_consent_still_records_the_revocation():
    """동의 기능 이전 링크(동의도 철회도 없음)도 끊기면 철회로 남는다."""
    link = _link(data_consent_at=None, data_consent_revoked_at=None)
    at = clock.now()

    data_consent_service.revoke(link, at=at)

    assert link.data_consent_revoked_at == at
    assert data_consent_service.blocks_access(link)


def test_a_new_consent_reopens_access_and_keeps_the_revocation_history():
    revoked_at = clock.now() - timedelta(days=2)
    link = _link(data_consent_at=None, data_consent_revoked_at=revoked_at)
    renewed = clock.now()

    data_consent_service.grant(link, renewed)

    assert link.data_consent_at == renewed
    assert link.data_consent_revoked_at == revoked_at
    assert not data_consent_service.blocks_access(link)


def test_granting_nothing_does_not_revive_an_old_consent():
    link = _link(
        data_consent_at=clock.now() - timedelta(days=40),
        data_consent_revoked_at=clock.now() - timedelta(days=10),
    )

    data_consent_service.grant(link, None)

    assert link.data_consent_at is None
    assert data_consent_service.blocks_access(link)


def test_a_legacy_link_without_consent_or_revocation_is_not_blocked():
    """#1022 이전 담당을 소급해서 막지 않는다."""
    assert not data_consent_service.blocks_access(
        _link(data_consent_at=None, data_consent_revoked_at=None)
    )


def test_a_consented_link_is_not_blocked():
    assert not data_consent_service.blocks_access(
        _link(data_consent_at=clock.now(), data_consent_revoked_at=None)
    )


def test_the_sql_clause_names_both_columns():
    compiled = str(data_consent_service.allows_access_clause())
    assert "data_consent_at IS NOT NULL" in compiled
    assert "data_consent_revoked_at IS NULL" in compiled


# ---------------------------------------------------------------------------
# DB 픽스처
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _cleanup(request):
    # 규칙 테스트는 DB 없이 돈다. DB 를 쓰는 테스트만 먼저 세션을 잡아 두어야
    # 정리가 세션이 닫히기 전에 끝난다.
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
        db_session.query(TrainerReportFeedback).filter(
            (TrainerReportFeedback.trainer_id.in_(user_ids))
            | (TrainerReportFeedback.member_id.in_(user_ids))
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


def _member(client) -> tuple[str, str]:
    """회원 하나. (id, token)"""
    email = f"{EMAIL_PREFIX}member-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={
            "email": email,
            "password": PASSWORD,
            "name": "동의 확인 회원",
            "phone": "010-1234-5678",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["id"], _login(client, email)


def _trainer(client, db_session) -> tuple[str, str]:
    """헬스장이 있는 트레이너 하나. (id, token)"""
    suffix = uuid4().hex[:10]
    email = f"{EMAIL_PREFIX}trainer-{suffix}@oncare.com"
    place = Place(
        id=f"{PLACE_PREFIX}{suffix}",
        name="동의 확인 헬스장",
        category="fitness",
        address="서울",
    )
    db_session.add(place)
    trainer = User(
        id=f"consent-trainer-{suffix}",
        email=email,
        name="동의 확인 트레이너",
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
    """회원이 코드를 띄우고 트레이너가 입력한다 — 동의가 함께 온다(#1634)."""
    issued = client.post("/v1/users/me/pairing-code", headers=_auth(member_token))
    assert issued.status_code == 200, issued.text
    redeemed = client.post(
        "/v1/trainer/pairing-code",
        json={"code": issued.json()["code"]},
        headers=_auth(trainer_token),
    )
    assert redeemed.status_code == 200, redeemed.text


def _link_of(db_session, trainer_id: str, member_id: str) -> TrainerClient:
    db_session.expire_all()
    return db_session.scalars(
        select(TrainerClient).where(
            TrainerClient.trainer_id == trainer_id,
            TrainerClient.member_id == member_id,
        )
    ).one()


def _linked(client, db_session) -> tuple[str, str, str, str]:
    """코드로 담당이 생긴 한 쌍. (member_id, member_token, trainer_id, trainer_token)"""
    member_id, member_token = _member(client)
    trainer_id, trainer_token = _trainer(client, db_session)
    _pair_by_code(client, member_token, trainer_token)
    link = _link_of(db_session, trainer_id, member_id)
    assert link.active is True
    assert link.data_consent_at is not None
    assert link.data_consent_revoked_at is None
    return member_id, member_token, trainer_id, trainer_token


def _diet(client, trainer_token: str, member_id: str):
    return client.get(
        f"/v1/trainer/clients/{member_id}/diet", headers=_auth(trainer_token)
    )


def _assert_revoked(link: TrainerClient, *, since: datetime) -> None:
    assert link.active is False
    assert link.data_consent_at is None
    assert link.data_consent_revoked_at is not None
    assert link.data_consent_revoked_at >= since


def _invite(client, trainer_token: str, member_id: str) -> str:
    response = client.post(
        "/v1/trainer/client-invites",
        json={"member_id": member_id},
        headers=_auth(trainer_token),
    )
    assert response.status_code == 201, response.text
    return response.json()["id"]


def _accept_invite(client, member_token: str, invite_id: str):
    return client.post(
        f"/v1/me/coach/invites/{invite_id}/accept",
        headers=_auth(member_token),
        json={"data_sharing_consent": True},
    )


# ---------------------------------------------------------------------------
# 끊기는 경로마다 철회
# ---------------------------------------------------------------------------


def test_member_releasing_the_trainer_revokes_consent(client, db_session):
    member_id, member_token, trainer_id, _ = _linked(client, db_session)
    before = clock.now()

    response = client.delete("/v1/me/coach/trainer", headers=_auth(member_token))

    assert response.status_code == 204, response.text
    _assert_revoked(_link_of(db_session, trainer_id, member_id), since=before)


def test_member_leaving_the_gym_revokes_consent(client, db_session):
    member_id, member_token, trainer_id, _ = _linked(client, db_session)
    before = clock.now()

    response = client.delete("/v1/me/coach", headers=_auth(member_token))

    assert response.status_code == 204, response.text
    _assert_revoked(_link_of(db_session, trainer_id, member_id), since=before)


def test_trainer_removing_the_member_revokes_consent(client, db_session):
    member_id, _, trainer_id, trainer_token = _linked(client, db_session)
    before = clock.now()

    response = client.delete(
        f"/v1/trainer/clients/{member_id}", headers=_auth(trainer_token)
    )

    assert response.status_code == 204, response.text
    _assert_revoked(_link_of(db_session, trainer_id, member_id), since=before)


def test_releasing_again_keeps_the_first_revocation_time(client, db_session):
    """해제는 멱등이다 — 두 번 눌러도 철회 시각이 밀리지 않는다."""
    member_id, member_token, trainer_id, _ = _linked(client, db_session)
    assert client.delete("/v1/me/coach/trainer", headers=_auth(member_token)).status_code == 204
    first = _link_of(db_session, trainer_id, member_id).data_consent_revoked_at

    assert client.delete("/v1/me/coach/trainer", headers=_auth(member_token)).status_code == 204

    assert _link_of(db_session, trainer_id, member_id).data_consent_revoked_at == first


def test_moving_to_another_trainer_revokes_the_old_link_only(client, db_session):
    """재배정 — 옛 트레이너의 동의는 철회되고 새 트레이너에게만 새 동의가 있다."""
    member_id, member_token, old_id, old_token = _linked(client, db_session)
    new_id, new_token = _trainer(client, db_session)

    assert client.delete("/v1/me/coach/trainer", headers=_auth(member_token)).status_code == 204
    _pair_by_code(client, member_token, new_token)

    old = _link_of(db_session, old_id, member_id)
    new = _link_of(db_session, new_id, member_id)
    assert old.active is False
    assert old.data_consent_at is None
    assert old.data_consent_revoked_at is not None
    assert new.active is True
    assert new.data_consent_at is not None
    assert new.data_consent_revoked_at is None

    blocked = _diet(client, old_token, member_id)
    assert blocked.status_code == 404
    assert blocked.json()["detail"] == GUARD_DETAIL
    assert _diet(client, new_token, member_id).status_code == 200


def test_member_withdrawal_leaves_no_consent_behind(client, db_session):
    """탈퇴하면 링크 행이 계정과 함께 지워진다 — 남는 동의가 없다."""
    member_id, member_token, trainer_id, _ = _linked(client, db_session)

    response = client.request(
        "DELETE", "/v1/users/me", json={"current_password": PASSWORD},
        headers=_auth(member_token),
    )

    assert response.status_code == 200, response.text
    db_session.expire_all()
    assert (
        db_session.scalar(
            select(TrainerClient.id).where(TrainerClient.member_id == member_id)
        )
        is None
    )


def test_trainer_withdrawal_leaves_no_consent_behind(client, db_session):
    member_id, member_token, trainer_id, trainer_token = _linked(client, db_session)

    response = client.request(
        "DELETE",
        "/v1/trainer/me",
        json={"current_password": PASSWORD},
        headers=_auth(trainer_token),
    )

    assert response.status_code == 200, response.text
    db_session.expire_all()
    assert (
        db_session.scalar(
            select(TrainerClient.id).where(TrainerClient.trainer_id == trainer_id)
        )
        is None
    )
    # 회원 쪽은 '담당 없음'이 된다.
    coach = client.get("/v1/me/coach", headers=_auth(member_token))
    assert coach.status_code == 404


# ---------------------------------------------------------------------------
# 되살릴 때는 새 동의만
# ---------------------------------------------------------------------------


def test_reconnecting_by_code_records_the_new_consent_not_the_old_one(
    client, db_session
):
    member_id, member_token, trainer_id, trainer_token = _linked(client, db_session)
    old_consent = _link_of(db_session, trainer_id, member_id).data_consent_at
    assert client.delete("/v1/me/coach/trainer", headers=_auth(member_token)).status_code == 204
    revoked_at = _link_of(db_session, trainer_id, member_id).data_consent_revoked_at

    _pair_by_code(client, member_token, trainer_token)

    link = _link_of(db_session, trainer_id, member_id)
    assert link.active is True
    assert link.data_consent_at is not None
    assert link.data_consent_at > old_consent
    assert link.data_consent_at >= revoked_at
    # 언제 철회했는지는 이력으로 남는다.
    assert link.data_consent_revoked_at == revoked_at
    assert _diet(client, trainer_token, member_id).status_code == 200


def test_reconnecting_by_invite_records_the_new_consent(client, db_session):
    member_id, member_token, trainer_id, trainer_token = _linked(client, db_session)
    assert client.delete("/v1/me/coach/trainer", headers=_auth(member_token)).status_code == 204
    revoked_at = _link_of(db_session, trainer_id, member_id).data_consent_revoked_at

    invite_id = _invite(client, trainer_token, member_id)
    accepted = _accept_invite(client, member_token, invite_id)

    assert accepted.status_code == 200, accepted.text
    link = _link_of(db_session, trainer_id, member_id)
    assert link.active is True
    assert link.data_consent_at is not None
    assert link.data_consent_at >= revoked_at
    assert _diet(client, trainer_token, member_id).status_code == 200


def test_reviving_without_a_new_consent_keeps_the_member_closed(client, db_session):
    """상담처럼 동의 시각 없이 되살아난 링크는 기록을 열지 않는다."""
    member_id, member_token, trainer_id, trainer_token = _linked(client, db_session)
    assert client.delete("/v1/me/coach/trainer", headers=_auth(member_token)).status_code == 204

    consultation_service.attach_member_to_trainer(
        db_session, trainer_id, member_id, consented_at=None
    )
    db_session.commit()

    link = _link_of(db_session, trainer_id, member_id)
    assert link.active is True
    assert link.data_consent_at is None
    assert data_consent_service.blocks_access(link)

    blocked = _diet(client, trainer_token, member_id)
    assert blocked.status_code == 404
    assert blocked.json()["detail"] == GUARD_DETAIL
    for path in ("/health-profile", "/chat", "/routines", "/memos"):
        denied = client.get(
            f"/v1/trainer/clients/{member_id}{path}", headers=_auth(trainer_token)
        )
        assert denied.status_code == 404, (path, denied.text)


def test_roster_shows_no_member_data_while_consent_is_missing(client, db_session):
    member_id, member_token, trainer_id, trainer_token = _linked(client, db_session)
    sent = client.post(
        "/v1/me/coach/chat",
        headers=_auth(member_token),
        json={"text": "철회 전에 보낸 말"},
    )
    assert sent.status_code == 201, sent.text
    assert client.delete("/v1/me/coach/trainer", headers=_auth(member_token)).status_code == 204
    consultation_service.attach_member_to_trainer(
        db_session, trainer_id, member_id, consented_at=None
    )
    db_session.commit()

    roster = client.get("/v1/trainer/clients", headers=_auth(trainer_token))

    assert roster.status_code == 200, roster.text
    row = next(r for r in roster.json() if r["id"] == member_id)
    assert row["last_message"] == ""
    assert row["last_message_at"] is None
    assert row["calories"] == 0
    assert row["signals"] == []


def test_accepting_an_invite_restores_consent_on_a_link_revived_without_one(
    client, db_session
):
    member_id, member_token, trainer_id, trainer_token = _linked(client, db_session)
    assert client.delete("/v1/me/coach/trainer", headers=_auth(member_token)).status_code == 204
    consultation_service.attach_member_to_trainer(
        db_session, trainer_id, member_id, consented_at=None
    )
    # 동의 없는 링크에 담당 요청을 넣으려면 대기 행이 있어야 한다 — 이미 담당인
    # 회원에게는 초대 API 가 막히므로 행을 직접 만든다.
    invite_id = f"tci-{uuid4().hex[:12]}"
    db_session.add(
        TrainerClientInvite(
            id=invite_id, trainer_id=trainer_id, member_id=member_id, status="pending"
        )
    )
    db_session.commit()

    accepted = _accept_invite(client, member_token, invite_id)

    assert accepted.status_code == 200, accepted.text
    link = _link_of(db_session, trainer_id, member_id)
    assert link.data_consent_at is not None
    assert not data_consent_service.blocks_access(link)
    assert _diet(client, trainer_token, member_id).status_code == 200


def test_a_code_restores_consent_on_a_link_revived_without_one(client, db_session):
    member_id, member_token, trainer_id, trainer_token = _linked(client, db_session)
    assert client.delete("/v1/me/coach/trainer", headers=_auth(member_token)).status_code == 204
    consultation_service.attach_member_to_trainer(
        db_session, trainer_id, member_id, consented_at=None
    )
    db_session.commit()

    _pair_by_code(client, member_token, trainer_token)

    link = _link_of(db_session, trainer_id, member_id)
    assert link.data_consent_at is not None
    assert _diet(client, trainer_token, member_id).status_code == 200


def test_a_code_for_a_consented_link_is_still_refused_as_duplicate(client, db_session):
    """동의가 살아 있는 담당에 코드를 다시 쓰면 예전처럼 '이미 담당'이다."""
    member_id, member_token, trainer_id, trainer_token = _linked(client, db_session)
    issued = client.post("/v1/users/me/pairing-code", headers=_auth(member_token))
    assert issued.status_code == 200, issued.text

    again = client.post(
        "/v1/trainer/pairing-code",
        json={"code": issued.json()["code"]},
        headers=_auth(trainer_token),
    )

    assert again.status_code == 409, again.text


# ---------------------------------------------------------------------------
# 트레이너 혼자 되살리지 못한다
# ---------------------------------------------------------------------------


def test_trainer_cannot_re_register_a_member_who_revoked(client, db_session):
    member_id, member_token, trainer_id, trainer_token = _linked(client, db_session)
    assert client.delete("/v1/me/coach/trainer", headers=_auth(member_token)).status_code == 204

    restored = client.put(
        f"/v1/trainer/clients/{member_id}/registration", headers=_auth(trainer_token)
    )

    assert restored.status_code == 409, restored.text
    assert "동의" in restored.json()["detail"]
    link = _link_of(db_session, trainer_id, member_id)
    assert link.active is False
    assert link.data_consent_at is None
    # 회원 앱에서도 코치가 되살아나지 않는다.
    assert client.get("/v1/me/coach", headers=_auth(member_token)).status_code == 404


def test_trainer_cannot_re_register_after_removing_the_member(client, db_session):
    member_id, _, trainer_id, trainer_token = _linked(client, db_session)
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
    assert _diet(client, trainer_token, member_id).status_code == 404


def test_legacy_detached_link_without_a_revocation_can_still_be_re_registered(
    client, db_session
):
    """철회 기록이 없는 옛 해제 링크는 예전처럼 재등록된다."""
    member_id, _ = _member(client)
    trainer_id, trainer_token = _trainer(client, db_session)
    db_session.add(
        TrainerClient(
            id=f"tc-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            active=False,
        )
    )
    db_session.commit()

    restored = client.put(
        f"/v1/trainer/clients/{member_id}/registration", headers=_auth(trainer_token)
    )

    assert restored.status_code == 204, restored.text
    assert _diet(client, trainer_token, member_id).status_code == 200


# ---------------------------------------------------------------------------
# 이미 주고받은 기록은 남는다
# ---------------------------------------------------------------------------


def test_revoking_keeps_sent_chat_and_reports(client, db_session):
    member_id, member_token, trainer_id, _ = _linked(client, db_session)
    chat_id = f"chat-{uuid4().hex[:12]}"
    report_id = f"report-{uuid4().hex[:12]}"
    db_session.add_all(
        [
            ChatMessage(
                id=chat_id,
                trainer_id=trainer_id,
                member_id=member_id,
                sender="trainer",
                body="지난주 리포트를 보냈어요",
            ),
            TrainerReportFeedback(
                id=report_id,
                trainer_id=trainer_id,
                member_id=member_id,
                week_start="2026-09-14",
                body="주간 리포트",
            ),
        ]
    )
    db_session.commit()

    assert client.delete("/v1/me/coach/trainer", headers=_auth(member_token)).status_code == 204

    db_session.expire_all()
    assert db_session.get(ChatMessage, chat_id) is not None
    assert db_session.get(TrainerReportFeedback, report_id) is not None


def test_revoking_keeps_the_member_record_itself(client, db_session):
    member_id, member_token, trainer_id, trainer_token = _linked(client, db_session)
    assert (
        client.delete(
            f"/v1/trainer/clients/{member_id}", headers=_auth(trainer_token)
        ).status_code
        == 204
    )

    db_session.expire_all()
    assert db_session.get(User, member_id) is not None
    me = client.get("/v1/users/me", headers=_auth(member_token))
    assert me.status_code == 200, me.text


def _memos_of_every_source(db_session, trainer_id: str, member_id: str) -> list[str]:
    """세 출처의 메모를 하나씩 남긴다. 만든 메모 id 를 돌려준다."""
    rows = [
        TrainerClientMemo(
            id=f"memo-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            body="어깨 가동 범위 다시 확인",
            source="trainer",
        ),
        TrainerClientMemo(
            id=f"memo-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            body="무릎 불편 감지",
            source="chat_insight",
            insight_id=f"insight-{uuid4().hex[:8]}",
            insight_kind="discomfort",
        ),
        TrainerClientMemo(
            id=f"memo-{uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            body="스쿼트 무릎 안쪽 모임",
            source="exercise_memo",
            ref_kind="member_log",
            ref_date="2026-09-28",
        ),
    ]
    db_session.add_all(rows)
    db_session.commit()
    return [row.id for row in rows]


def _memos(client, trainer_token: str, member_id: str):
    return client.get(
        f"/v1/trainer/clients/{member_id}/memos", headers=_auth(trainer_token)
    )


@pytest.mark.parametrize(
    "who", ["member_releases", "member_leaves_gym", "trainer_removes"]
)
def test_revoking_keeps_memos_of_every_source_but_closes_them(
    client, db_session, who
):
    """담당 해제(= 동의 철회)는 메모를 지우지 않고 열람만 막는다. (#2520)

    끊은 쪽이 누구든, 출처(직접·채팅 감지·운동 기록)가 무엇이든 같다.
    """
    member_id, member_token, trainer_id, trainer_token = _linked(client, db_session)
    memo_ids = _memos_of_every_source(db_session, trainer_id, member_id)

    if who == "member_releases":
        response = client.delete("/v1/me/coach/trainer", headers=_auth(member_token))
    elif who == "member_leaves_gym":
        response = client.delete("/v1/me/coach", headers=_auth(member_token))
    else:
        response = client.delete(
            f"/v1/trainer/clients/{member_id}", headers=_auth(trainer_token)
        )
    assert response.status_code == 204, response.text

    db_session.expire_all()
    for memo_id in memo_ids:
        assert db_session.get(TrainerClientMemo, memo_id) is not None
    blocked = _memos(client, trainer_token, member_id)
    assert blocked.status_code == 404
    assert blocked.json()["detail"] == GUARD_DETAIL


def test_memos_stay_closed_when_the_trainer_re_registers_alone(client, db_session):
    """트레이너 혼자서는 되살릴 수 없으니 메모도 다시 열리지 않는다. (#2520)"""
    member_id, _, trainer_id, trainer_token = _linked(client, db_session)
    _memos_of_every_source(db_session, trainer_id, member_id)
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
    assert _memos(client, trainer_token, member_id).status_code == 404


def test_a_new_consent_brings_back_the_old_memos(client, db_session):
    """회원이 다시 동의해 같은 트레이너와 이어지면 옛 메모가 그대로 보인다. (#2520)

    채팅·리포트와 같은 기준이다 — 철회는 앞으로의 열람만 막는다.
    """
    member_id, member_token, trainer_id, trainer_token = _linked(client, db_session)
    memo_ids = _memos_of_every_source(db_session, trainer_id, member_id)
    assert client.delete("/v1/me/coach/trainer", headers=_auth(member_token)).status_code == 204

    _pair_by_code(client, member_token, trainer_token)

    response = _memos(client, trainer_token, member_id)
    assert response.status_code == 200, response.text
    by_id = {memo["id"]: memo["source"] for memo in response.json()}
    assert set(by_id) == set(memo_ids)
    assert set(by_id.values()) == {"trainer", "chat_insight", "exercise_memo"}


def test_another_trainer_does_not_see_the_old_memos(client, db_session):
    """메모는 쓴 트레이너의 것이다 — 새 담당에게 넘어가지 않는다. (#2520)"""
    member_id, member_token, old_id, _ = _linked(client, db_session)
    _memos_of_every_source(db_session, old_id, member_id)
    new_id, new_token = _trainer(client, db_session)
    assert client.delete("/v1/me/coach/trainer", headers=_auth(member_token)).status_code == 204

    _pair_by_code(client, member_token, new_token)

    response = _memos(client, new_token, member_id)
    assert response.status_code == 200, response.text
    assert response.json() == []


def test_trainer_withdrawal_removes_the_memos(client, db_session):
    """트레이너 탈퇴는 `trainer_id` CASCADE 로 그 트레이너의 메모를 함께 지운다. (#2520)"""
    member_id, _, trainer_id, trainer_token = _linked(client, db_session)
    memo_ids = _memos_of_every_source(db_session, trainer_id, member_id)

    response = client.request(
        "DELETE", "/v1/trainer/me", json={"current_password": PASSWORD},
        headers=_auth(trainer_token),
    )

    assert response.status_code == 200, response.text
    db_session.expire_all()
    for memo_id in memo_ids:
        assert db_session.get(TrainerClientMemo, memo_id) is None


def test_member_withdrawal_removes_the_memos(client, db_session):
    """회원 탈퇴는 `member_id` CASCADE 로 그 회원에 대한 메모를 함께 지운다. (#2520)"""
    member_id, member_token, trainer_id, _ = _linked(client, db_session)
    memo_ids = _memos_of_every_source(db_session, trainer_id, member_id)

    response = client.request(
        "DELETE", "/v1/users/me", json={"current_password": PASSWORD},
        headers=_auth(member_token),
    )

    assert response.status_code == 200, response.text
    db_session.expire_all()
    for memo_id in memo_ids:
        assert db_session.get(TrainerClientMemo, memo_id) is None


# ---------------------------------------------------------------------------
# 마이그레이션
# ---------------------------------------------------------------------------


def test_migration_clears_old_consent_on_detached_links(db_session, monkeypatch):
    migration = importlib.import_module(
        "migrations.versions.0097_data_consent_revocation"
    )
    assert migration.down_revision == "0096_notification_templates"
    schema = f"consent1631_{uuid4().hex[:12]}"
    metadata = sa.MetaData(schema=schema)
    links = sa.Table(
        "trainer_clients",
        metadata,
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("active", sa.Boolean, nullable=False),
        sa.Column("data_consent_at", sa.DateTime(timezone=True), nullable=True),
    )
    consented = clock.now() - timedelta(days=60)

    engine = db_session.get_bind()
    with engine.begin() as connection:
        connection.execute(sa.schema.CreateSchema(schema))
        try:
            metadata.create_all(connection)
            connection.execute(
                links.insert(),
                [
                    {"id": "live", "active": True, "data_consent_at": consented},
                    {"id": "legacy-live", "active": True, "data_consent_at": None},
                    {"id": "ended", "active": False, "data_consent_at": consented},
                    {"id": "legacy-ended", "active": False, "data_consent_at": None},
                ],
            )
            connection.exec_driver_sql(f'SET LOCAL search_path TO "{schema}"')
            operations = Operations(MigrationContext.configure(connection))
            monkeypatch.setattr(migration, "op", operations)

            migration.upgrade()

            rows = {
                row.id: row
                for row in connection.execute(
                    sa.text(
                        "SELECT id, data_consent_at, data_consent_revoked_at "
                        "FROM trainer_clients"
                    )
                )
            }
            assert rows["live"].data_consent_at == consented
            assert rows["live"].data_consent_revoked_at is None
            assert rows["legacy-live"].data_consent_at is None
            assert rows["legacy-live"].data_consent_revoked_at is None
            for ended in ("ended", "legacy-ended"):
                assert rows[ended].data_consent_at is None
                assert rows[ended].data_consent_revoked_at is not None

            migration.downgrade()
            inspector = inspect(connection)
            assert "data_consent_revoked_at" not in {
                column["name"]
                for column in inspector.get_columns("trainer_clients", schema=schema)
            }
        finally:
            connection.execute(sa.schema.DropSchema(schema, cascade=True))
