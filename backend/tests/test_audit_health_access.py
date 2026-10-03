"""트레이너 건강정보 열람·동의·탈퇴·비밀번호 변경 감사 기록. (#2830)

감사 로그는 로그인·가입 같은 인증 이벤트만 남겼다. 여기서 보는 것:

* 트레이너가 담당 회원의 식단·운동·신체 정보·리포트를 조회하면 누가·누구의·
  무엇을·언제 봤는지 남는다. 묶음 시간 안의 같은 조회는 한 번만 남는다.
* 남의 회원·해제된 회원 요청(404)은 열람이 아니므로 남지 않는다.
* 동의 발급(경로별)·철회(주체별)·탈퇴·비밀번호 변경이 남고, 링크·계정 행이
  지워져도 기록은 유지된다.
* 기록에는 식단 내용 같은 개인정보 본문이 들어가지 않는다.
* 보존 기간이 지난 기록은 정리된다.
* 감사 기록 실패가 조회를 깨지 않는다.

DB 가 필요하므로 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

from datetime import timedelta
from uuid import uuid4

import pytest
from sqlalchemy import or_, select

from app.core import clock
from app.core.config import get_settings
from app.core.security import create_access_token, hash_password
from app.models.models import (
    AuditLog,
    DietEntry,
    Notification,
    TrainerClient,
    TrainerProfile,
    User,
)
from app.services import audit, consultation_service, data_consent_service

PREFIX = "audit2830-"
PASSWORD = "audit2830-pw-1234"


@pytest.fixture(autouse=True)
def _cleanup(db_session):
    yield
    db_session.rollback()
    ids = [
        row[0]
        for row in db_session.query(User.id).filter(User.id.like(f"{PREFIX}%")).all()
    ]
    db_session.query(AuditLog).filter(
        or_(
            AuditLog.user_id.like(f"{PREFIX}%"),
            AuditLog.target_user_id.like(f"{PREFIX}%"),
        )
    ).delete(synchronize_session=False)
    if ids:
        db_session.query(Notification).filter(
            Notification.user_id.in_(ids)
        ).delete(synchronize_session=False)
        db_session.query(TrainerClient).filter(
            TrainerClient.trainer_id.in_(ids) | TrainerClient.member_id.in_(ids)
        ).delete(synchronize_session=False)
        db_session.query(TrainerProfile).filter(
            TrainerProfile.trainer_id.in_(ids)
        ).delete(synchronize_session=False)
        db_session.query(User).filter(User.id.in_(ids)).delete(
            synchronize_session=False
        )
    db_session.commit()


def _user(db_session, role: str) -> User:
    suffix = uuid4().hex[:10]
    user = User(
        id=f"{PREFIX}{role[0]}-{suffix}",
        email=f"{PREFIX}{role}-{suffix}@example.com",
        name="감사회원" if role == "member" else "감사트레이너",
        hashed_password=hash_password(PASSWORD),
        role=role,
        is_active=True,
    )
    db_session.add(user)
    db_session.flush()
    if role == "trainer":
        db_session.add(TrainerProfile(trainer_id=user.id))
    db_session.commit()
    return user


def _link(db_session, trainer: User, member: User, **fields) -> TrainerClient:
    values = {"active": True, "data_consent_at": clock.now() - timedelta(days=1)}
    values.update(fields)
    link = TrainerClient(
        id=f"tc-{PREFIX}{uuid4().hex[:10]}",
        trainer_id=trainer.id,
        member_id=member.id,
        **values,
    )
    db_session.add(link)
    db_session.commit()
    return link


def _auth(user: User) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(user.id)}"}


def _rows(db_session, event: str, **filters) -> list[AuditLog]:
    db_session.expire_all()
    query = select(AuditLog).where(AuditLog.event == event)
    for column, value in filters.items():
        query = query.where(getattr(AuditLog, column) == value)
    return list(db_session.scalars(query.order_by(AuditLog.id)).all())


@pytest.fixture
def pair(db_session):
    trainer = _user(db_session, "trainer")
    member = _user(db_session, "member")
    _link(db_session, trainer, member)
    return trainer, member


# ---- 열람 기록 ----


@pytest.mark.parametrize(
    ("path", "resource"),
    [
        ("diet?date=2026-09-30", "diet"),
        ("diet/days", "diet"),
        ("exercise/weeks", "exercise"),
        ("history", "exercise"),
        ("health-profile", "body"),
        ("reports/sent", "report"),
    ],
)
def test_reading_a_clients_records_is_audited(
    client, db_session, pair, path, resource
):
    trainer, member = pair

    response = client.get(
        f"/v1/trainer/clients/{member.id}/{path}", headers=_auth(trainer)
    )

    assert response.status_code == 200, response.text
    rows = _rows(
        db_session, audit.CLIENT_READ, user_id=trainer.id, target_user_id=member.id
    )
    assert [r.resource for r in rows] == [resource]
    assert rows[0].success is True
    assert rows[0].created_at is not None


def test_the_record_holds_no_personal_content(client, db_session, pair):
    trainer, member = pair
    db_session.add(DietEntry(
        id=f"{PREFIX}diet-{uuid4().hex[:8]}",
        user_id=member.id,
        date="2026-09-30",
        meal_type="lunch",
        foods_json='[{"name": "비밀 김치찌개", "calories": 500}]',
        total_calories=500,
    ))
    db_session.commit()

    response = client.get(
        f"/v1/trainer/clients/{member.id}/diet?date=2026-09-30",
        headers=_auth(trainer),
    )

    assert response.status_code == 200, response.text
    (row,) = _rows(db_session, audit.CLIENT_READ, target_user_id=member.id)
    assert "김치찌개" not in (row.detail or "")
    assert row.detail == ""
    assert row.resource == "diet"


def test_repeated_reads_inside_the_window_are_recorded_once(
    client, db_session, pair
):
    trainer, member = pair

    for _ in range(3):
        assert client.get(
            f"/v1/trainer/clients/{member.id}/diet/days", headers=_auth(trainer)
        ).status_code == 200
    # 다른 자원은 따로 남는다.
    assert client.get(
        f"/v1/trainer/clients/{member.id}/exercise/weeks", headers=_auth(trainer)
    ).status_code == 200

    rows = _rows(db_session, audit.CLIENT_READ, target_user_id=member.id)
    assert sorted(r.resource for r in rows) == ["diet", "exercise"]


def test_a_read_after_the_window_is_recorded_again(client, db_session, pair):
    trainer, member = pair
    window = get_settings().audit_read_dedupe_minutes
    db_session.add(AuditLog(
        event=audit.CLIENT_READ,
        user_id=trainer.id,
        target_user_id=member.id,
        resource="diet",
        created_at=clock.now() - timedelta(minutes=window + 1),
    ))
    db_session.commit()

    assert client.get(
        f"/v1/trainer/clients/{member.id}/diet/days", headers=_auth(trainer)
    ).status_code == 200

    assert len(_rows(db_session, audit.CLIENT_READ, target_user_id=member.id)) == 2


def test_dedupe_can_be_turned_off(client, db_session, pair, monkeypatch):
    trainer, member = pair
    monkeypatch.setattr(get_settings(), "audit_read_dedupe_minutes", 0)

    for _ in range(2):
        client.get(
            f"/v1/trainer/clients/{member.id}/diet/days", headers=_auth(trainer)
        )

    assert len(_rows(db_session, audit.CLIENT_READ, target_user_id=member.id)) == 2


def test_requests_that_end_in_404_are_not_reads(client, db_session):
    trainer = _user(db_session, "trainer")
    other = _user(db_session, "trainer")
    released = _user(db_session, "member")
    revoked = _user(db_session, "member")
    stranger = _user(db_session, "member")
    _link(db_session, trainer, released, active=False, data_consent_at=None,
          data_consent_revoked_at=clock.now())
    _link(db_session, trainer, revoked, data_consent_at=None,
          data_consent_revoked_at=clock.now())
    _link(db_session, other, stranger)

    for member in (released, revoked, stranger):
        response = client.get(
            f"/v1/trainer/clients/{member.id}/diet/days", headers=_auth(trainer)
        )
        assert response.status_code == 404
        assert _rows(db_session, audit.CLIENT_READ, target_user_id=member.id) == []


def test_writing_routes_are_not_read_audited(client, db_session, pair):
    """루틴·메모처럼 트레이너가 쓰는 기록은 열람 감사 대상이 아니다."""
    trainer, member = pair

    assert client.get(
        f"/v1/trainer/clients/{member.id}/memos", headers=_auth(trainer)
    ).status_code == 200

    assert _rows(db_session, audit.CLIENT_READ, target_user_id=member.id) == []


def test_an_audit_failure_does_not_break_the_read(
    client, db_session, pair, monkeypatch
):
    trainer, member = pair

    def broken(*args, **kwargs):
        raise RuntimeError("audit store down")

    monkeypatch.setattr(audit, "stage", broken)

    response = client.get(
        f"/v1/trainer/clients/{member.id}/diet/days", headers=_auth(trainer)
    )

    assert response.status_code == 200, response.text
    assert _rows(db_session, audit.CLIENT_READ, target_user_id=member.id) == []


# ---- 동의 발급·철회 ----


@pytest.mark.parametrize(
    "via",
    [
        data_consent_service.VIA_PAIRING,
        data_consent_service.VIA_INVITE,
    ],
)
def test_a_new_link_with_consent_records_the_grant(db_session, via):
    trainer = _user(db_session, "trainer")
    member = _user(db_session, "member")

    consultation_service.attach_member_to_trainer(
        db_session, trainer.id, member.id, consented_at=clock.now(), via=via
    )
    db_session.commit()

    (row,) = _rows(db_session, audit.CONSENT_GRANT, target_user_id=member.id)
    assert row.user_id == member.id
    assert f"via={via}" in row.detail
    assert f"trainer={trainer.id}" in row.detail


def test_reviving_a_link_records_the_new_grant(db_session):
    trainer = _user(db_session, "trainer")
    member = _user(db_session, "member")
    _link(db_session, trainer, member, active=False, data_consent_at=None,
          data_consent_revoked_at=clock.now() - timedelta(days=3))

    consultation_service.attach_member_to_trainer(
        db_session, trainer.id, member.id, consented_at=clock.now(),
        via=data_consent_service.VIA_PAIRING,
    )
    db_session.commit()

    (row,) = _rows(db_session, audit.CONSENT_GRANT, target_user_id=member.id)
    assert "via=pairing" in row.detail


def test_reviving_without_consent_records_no_grant(db_session):
    trainer = _user(db_session, "trainer")
    member = _user(db_session, "member")
    _link(db_session, trainer, member, active=False, data_consent_at=None,
          data_consent_revoked_at=clock.now() - timedelta(days=3))

    consultation_service.attach_member_to_trainer(
        db_session, trainer.id, member.id, consented_at=None
    )
    db_session.commit()

    assert _rows(db_session, audit.CONSENT_GRANT, target_user_id=member.id) == []


def test_a_grant_rolled_back_leaves_no_record(db_session):
    """감사 기록은 동의와 같은 트랜잭션이다 — 롤백되면 둘 다 없다."""
    trainer = _user(db_session, "trainer")
    member = _user(db_session, "member")

    consultation_service.attach_member_to_trainer(
        db_session, trainer.id, member.id, consented_at=clock.now(), via="invite"
    )
    db_session.rollback()

    assert _rows(db_session, audit.CONSENT_GRANT, target_user_id=member.id) == []


def test_trainer_release_records_a_revoke_by_the_trainer(client, db_session, pair):
    trainer, member = pair

    response = client.delete(
        f"/v1/trainer/clients/{member.id}", headers=_auth(trainer)
    )

    assert response.status_code == 204, response.text
    (row,) = _rows(db_session, audit.CONSENT_REVOKE, target_user_id=member.id)
    assert row.user_id == trainer.id
    assert "by=trainer" in row.detail


def test_member_disconnect_records_a_revoke_by_the_member(client, db_session, pair):
    trainer, member = pair

    response = client.delete("/v1/me/coach/trainer", headers=_auth(member))

    assert response.status_code == 204, response.text
    (row,) = _rows(db_session, audit.CONSENT_REVOKE, target_user_id=member.id)
    assert row.user_id == member.id
    assert "by=member" in row.detail
    assert f"trainer={trainer.id}" in row.detail


def test_a_second_release_does_not_record_again(db_session, pair):
    _, member = pair
    link = db_session.scalar(
        select(TrainerClient).where(TrainerClient.member_id == member.id)
    )

    data_consent_service.revoke(link, by=data_consent_service.BY_MEMBER)
    db_session.commit()
    data_consent_service.revoke(link, by=data_consent_service.BY_MEMBER)
    db_session.commit()

    assert len(_rows(db_session, audit.CONSENT_REVOKE, target_user_id=member.id)) == 1


# ---- 탈퇴·비밀번호 변경 ----


def test_member_withdrawal_is_kept_after_the_account_is_gone(
    client, db_session, pair
):
    trainer, member = pair
    member_id = member.id

    response = client.request(
        "DELETE", "/v1/users/me", json={"current_password": PASSWORD},
        headers=_auth(member),
    )

    assert response.status_code == 200, response.text
    db_session.expire_all()
    assert db_session.get(User, member_id) is None
    assert db_session.scalar(
        select(TrainerClient).where(TrainerClient.member_id == member_id)
    ) is None
    (withdraw,) = _rows(db_session, audit.ACCOUNT_WITHDRAW, user_id=member_id)
    assert withdraw.target_user_id == member_id
    assert withdraw.detail == "role=member"
    (revoke,) = _rows(db_session, audit.CONSENT_REVOKE, target_user_id=member_id)
    assert "by=member" in revoke.detail
    assert "reason=withdraw" in revoke.detail
    assert f"trainer={trainer.id}" in revoke.detail


def test_trainer_withdrawal_records_each_live_consent(client, db_session):
    trainer = _user(db_session, "trainer")
    consented = _user(db_session, "member")
    already_revoked = _user(db_session, "member")
    _link(db_session, trainer, consented)
    _link(db_session, trainer, already_revoked, data_consent_at=None,
          data_consent_revoked_at=clock.now() - timedelta(days=1))
    trainer_id = trainer.id

    response = client.request(
        "DELETE", "/v1/trainer/me", json={"current_password": PASSWORD},
        headers=_auth(trainer),
    )

    assert response.status_code == 200, response.text
    (withdraw,) = _rows(db_session, audit.ACCOUNT_WITHDRAW, user_id=trainer_id)
    assert withdraw.detail == "role=trainer"
    revokes = _rows(db_session, audit.CONSENT_REVOKE, user_id=trainer_id)
    # 이미 철회된 동의는 다시 적지 않는다.
    assert [r.target_user_id for r in revokes] == [consented.id]
    assert "reason=withdraw" in revokes[0].detail


def test_trainer_password_change_is_audited(client, db_session):
    trainer = _user(db_session, "trainer")

    response = client.post(
        "/v1/trainer/me/password",
        json={"current_password": PASSWORD, "new_password": "audit2830-new-pw-5678"},
        headers=_auth(trainer),
    )

    assert response.status_code == 200, response.text
    (row,) = _rows(db_session, audit.PASSWORD_CHANGE, user_id=trainer.id)
    assert row.success is True
    assert "audit2830-new-pw" not in (row.detail or "")


def test_a_failed_password_change_is_not_recorded_as_a_change(client, db_session):
    trainer = _user(db_session, "trainer")

    response = client.post(
        "/v1/trainer/me/password",
        json={"current_password": "wrong", "new_password": "audit2830-new-pw-5678"},
        headers=_auth(trainer),
    )

    assert response.status_code == 400
    # 바뀐 기록(success=True)은 없고, 틀린 시도는 실패로만 남는다(#2913 계정 단위 잠금).
    assert _rows(db_session, audit.PASSWORD_CHANGE, user_id=trainer.id, success=True) == []
    failed = _rows(db_session, audit.PASSWORD_CHANGE, user_id=trainer.id, success=False)
    assert [row.detail for row in failed] == ["current_password_mismatch"]


# ---- 보존 기간 ----


def _aged(db_session, event: str, days: int) -> int:
    row = AuditLog(
        event=event,
        user_id=f"{PREFIX}purge-{uuid4().hex[:8]}",
        created_at=clock.now() - timedelta(days=days),
    )
    db_session.add(row)
    db_session.commit()
    return row.id


def _alive(db_session, row_id: int) -> bool:
    db_session.expire_all()
    return db_session.get(AuditLog, row_id) is not None


def test_expired_records_are_purged_by_category(db_session, monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "audit_retention_days", 365)
    monkeypatch.setattr(settings, "audit_sensitive_retention_days", 730)
    old_login = _aged(db_session, "auth.login", 400)
    recent_login = _aged(db_session, "auth.login", 100)
    read_kept = _aged(db_session, audit.CLIENT_READ, 400)
    read_expired = _aged(db_session, audit.CLIENT_READ, 800)
    consent_expired = _aged(db_session, audit.CONSENT_GRANT, 800)

    removed = audit.purge_expired(db_session)

    assert removed >= 3
    assert not _alive(db_session, old_login)
    assert _alive(db_session, recent_login)
    # 민감정보 처리 기록은 접속 기록보다 오래 남는다.
    assert _alive(db_session, read_kept)
    assert not _alive(db_session, read_expired)
    assert not _alive(db_session, consent_expired)


def test_zero_retention_keeps_everything(db_session, monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "audit_retention_days", 0)
    monkeypatch.setattr(settings, "audit_sensitive_retention_days", 0)
    ancient = _aged(db_session, "auth.login", 5000)

    assert audit.purge_expired(db_session) == 0
    assert _alive(db_session, ancient)
