"""트레이너 운영자 승인. (#2825)

공개 가입으로 생긴 트레이너는 승인 전까지 회원 데이터로 이어지는 네 자리에서
빠진다 — 디렉터리(목록·추천·상세), 상담 대상, 담당 요청, 연결 코드. 운영자는
관리자 엔드포인트로 승인·반려한다.

여기서 보는 것:

  * 가입 직후는 pending 이고 `/trainer/me` 가 그 상태를 싣는다.
  * pending·rejected 트레이너는 네 자리 어디에서도 회원에게 닿지 않는다.
  * 승인하면 그대로 열린다(가입 → 승인 → 상담까지 한 줄로).
  * 승인·반려는 관리자만 — 회원·트레이너 403, 미인증 401.
  * 승인 뒤 보낸 담당 요청은 반려되면 수락할 수 없다.

DB 가 필요하므로 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core.security import hash_password
from app.models.models import (
    AuditLog,
    ConsultationRequest,
    MemberGym,
    MemberPairingCode,
    Notification,
    Place,
    TrainerClient,
    TrainerClientInvite,
    TrainerProfile,
    User,
)

EMAIL_PREFIX = "verify-test-"
PLACE_PREFIX = "verify-place-"
PASSWORD = "verify-pw-1234"


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
        db_session.query(ConsultationRequest).filter(
            (ConsultationRequest.member_id.in_(user_ids))
            | (ConsultationRequest.trainer_id.in_(user_ids))
            | (ConsultationRequest.decided_by.in_(user_ids))
        ).delete(synchronize_session=False)
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


def _gym(db_session) -> Place:
    place = Place(
        id=f"{PLACE_PREFIX}{uuid4().hex[:10]}",
        name="승인 테스트 헬스장",
        category="fitness",
        address="서울",
    )
    db_session.add(place)
    db_session.commit()
    return place


def _sign_up_trainer(client, gym: Place) -> tuple[str, str]:
    """공개 가입 → 소속 선택. (id, token) — 승인 대기 상태로 끝난다."""
    email = f"{EMAIL_PREFIX}trainer-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/trainer/register",
        json={"email": email, "password": PASSWORD, "name": "가입 트레이너"},
    )
    assert response.status_code == 201, response.text
    token = _login(client, email)
    picked = client.put(
        "/v1/trainer/me/gym", headers=_auth(token), json={"gym_id": gym.id}
    )
    assert picked.status_code == 200, picked.text
    return response.json()["id"], token


def _seeded_trainer(db_session, gym: Place) -> tuple[User, str]:
    """운영자가 넣은 트레이너(ORM 기본값 경로). (user, email)"""
    suffix = uuid4().hex[:10]
    email = f"{EMAIL_PREFIX}seeded-{suffix}@oncare.com"
    trainer = User(
        id=f"verify-trainer-{suffix}",
        email=email,
        name="시드 트레이너",
        hashed_password=hash_password(PASSWORD),
        role="trainer",
        is_active=True,
    )
    db_session.add(trainer)
    db_session.flush()
    db_session.add(TrainerProfile(trainer_id=trainer.id, gym_id=gym.id))
    db_session.commit()
    return trainer, email


def _member(client) -> tuple[str, str]:
    email = f"{EMAIL_PREFIX}member-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": "승인 회원"},
    )
    assert response.status_code == 201, response.text
    return response.json()["id"], _login(client, email)


def _admin(client, db_session) -> tuple[str, str]:
    """관리자 하나. 운영에선 ADMIN_EMAILS 가 부팅 때 승격한다."""
    member_id, _ = _member(client)
    user = db_session.get(User, member_id)
    user.is_admin = True
    db_session.commit()
    return member_id, _login(client, user.email)


def _approve(client, admin_token: str, trainer_id: str):
    return client.post(
        f"/v1/admin/trainers/{trainer_id}/approve", headers=_auth(admin_token)
    )


def _reject(client, admin_token: str, trainer_id: str, reason: str = ""):
    return client.post(
        f"/v1/admin/trainers/{trainer_id}/reject",
        headers=_auth(admin_token),
        json={"reason": reason},
    )


def _directory_ids(client, member_token: str) -> set[str]:
    response = client.get("/v1/trainers", headers=_auth(member_token))
    assert response.status_code == 200, response.text
    return {row["id"] for row in response.json()}


def _gym_trainer_ids(client, member_token: str, gym_id: str) -> set[str]:
    response = client.get(f"/v1/gyms/{gym_id}/trainers", headers=_auth(member_token))
    assert response.status_code == 200, response.text
    return {row["id"] for row in response.json()}


def _request_consultation(client, member_token: str, trainer_id: str):
    from tests.test_consultation_decision import _open_slot

    return client.post(
        "/v1/consultations",
        headers=_auth(member_token),
        json={
            "trainer_id": trainer_id,
            "exercise_goal": "strength",
            "health_purpose_type": "general",
            "health_purpose_detail": None,
            "slot_id": _open_slot(trainer_id).id,
            "message": "상담 부탁드립니다.",
            "data_sharing_consent": True,
        },
    )


def _issue_code(client, member_token: str) -> str:
    response = client.post("/v1/users/me/pairing-code", headers=_auth(member_token))
    assert response.status_code == 200, response.text
    return response.json()["code"]


def _assert_not_approved(response) -> None:
    assert response.status_code == 403, response.text
    assert response.json()["detail"]["code"] == "trainer_not_approved"


# ---------------------------------------------------------------------------
# 규칙(DB 없이)
# ---------------------------------------------------------------------------


def test_unsaved_profile_reads_as_pending():
    """상태가 비어 있으면 승인으로 읽지 않는다 — 닫힌 쪽이 기본이다."""
    from app.services import trainer_verification_service

    out = trainer_verification_service.to_out(TrainerProfile(trainer_id="t"))
    assert out.status == "pending"
    assert out.decided_at is None
    assert out.note == ""


def test_rejection_note_is_carried_to_the_trainer():
    from app.services import trainer_verification_service

    profile = TrainerProfile(
        trainer_id="t", verification_status="rejected", verification_note="서류 보완"
    )
    out = trainer_verification_service.to_out(profile)
    assert (out.status, out.note) == ("rejected", "서류 보완")


def test_reject_reason_is_capped():
    from pydantic import ValidationError

    from app.schemas.trainer_verification import TrainerRejectIn

    assert TrainerRejectIn().reason == ""
    with pytest.raises(ValidationError):
        TrainerRejectIn(reason="가" * 301)


def test_migration_backfills_existing_trainers_as_approved():
    """기존 트레이너가 마이그레이션만으로 회원 앱에서 사라지면 안 된다."""
    import importlib.util
    from pathlib import Path

    path = (
        Path(__file__).resolve().parents[1]
        / "migrations/versions/0136_trainer_verification.py"
    )
    source = path.read_text(encoding="utf-8")
    spec = importlib.util.spec_from_file_location("m0124", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    assert module.revision == "0136_trainer_verification"
    # 칸을 approved 기본값으로 만든 뒤(백필) pending 으로 바꾼다.
    assert source.index('server_default="approved"') < source.index(
        'server_default="pending"'
    )


# ---------------------------------------------------------------------------
# 가입 직후
# ---------------------------------------------------------------------------


def test_signup_starts_pending_and_me_reports_it(client, db_session):
    gym = _gym(db_session)
    trainer_id, token = _sign_up_trainer(client, gym)

    profile = db_session.scalar(
        select(TrainerProfile).where(TrainerProfile.trainer_id == trainer_id)
    )
    assert profile.verification_status == "pending"
    assert profile.verification_decided_at is None
    assert profile.verification_decided_by is None

    me = client.get("/v1/trainer/me", headers=_auth(token))
    assert me.status_code == 200, me.text
    assert me.json()["verification"] == {
        "status": "pending",
        "decided_at": None,
        "note": "",
    }


def test_seeded_trainer_defaults_to_approved(client, db_session):
    """운영자가 직접 넣는 경로(시드)는 승인 상태다 — 데모 트레이너가 그대로 보인다."""
    gym = _gym(db_session)
    trainer, email = _seeded_trainer(db_session, gym)

    me = client.get("/v1/trainer/me", headers=_auth(_login(client, email)))
    assert me.status_code == 200, me.text
    assert me.json()["verification"]["status"] == "approved"

    _, member_token = _member(client)
    assert trainer.id in _directory_ids(client, member_token)


# ---------------------------------------------------------------------------
# 승인 전 — 네 자리 모두 닫힘
# ---------------------------------------------------------------------------


def test_pending_trainer_is_hidden_from_directory(client, db_session):
    gym = _gym(db_session)
    trainer_id, _ = _sign_up_trainer(client, gym)
    _, member_token = _member(client)

    assert trainer_id not in _directory_ids(client, member_token)
    assert trainer_id not in _gym_trainer_ids(client, member_token, gym.id)

    recommended = client.get("/v1/trainers/recommended", headers=_auth(member_token))
    assert recommended.status_code == 200, recommended.text
    assert trainer_id not in {row["id"] for row in recommended.json()}

    detail = client.get(f"/v1/trainers/{trainer_id}", headers=_auth(member_token))
    assert detail.status_code == 404, detail.text


def test_pending_trainer_cannot_be_a_consultation_target(client, db_session):
    gym = _gym(db_session)
    trainer_id, _ = _sign_up_trainer(client, gym)
    _, member_token = _member(client)

    response = _request_consultation(client, member_token, trainer_id)
    assert response.status_code == 404, response.text
    assert (
        db_session.scalar(
            select(ConsultationRequest).where(
                ConsultationRequest.trainer_id == trainer_id
            )
        )
        is None
    )


def test_pending_trainer_cannot_use_a_pairing_code(client, db_session):
    gym = _gym(db_session)
    trainer_id, trainer_token = _sign_up_trainer(client, gym)
    member_id, member_token = _member(client)
    code = _issue_code(client, member_token)

    _assert_not_approved(
        client.post(
            "/v1/trainer/pairing-code/preview",
            json={"code": code},
            headers=_auth(trainer_token),
        )
    )
    _assert_not_approved(
        client.post(
            "/v1/trainer/pairing-code",
            json={"code": code},
            headers=_auth(trainer_token),
        )
    )
    # 막힌 시도는 코드를 태우지 않고 담당도 만들지 않는다.
    assert (
        db_session.scalar(
            select(TrainerClient).where(
                TrainerClient.trainer_id == trainer_id,
                TrainerClient.member_id == member_id,
            )
        )
        is None
    )
    assert (
        db_session.scalar(
            select(MemberPairingCode).where(MemberPairingCode.member_id == member_id)
        )
        is not None
    )


def test_pending_trainer_cannot_send_a_client_invite(client, db_session):
    gym = _gym(db_session)
    trainer_id, trainer_token = _sign_up_trainer(client, gym)
    member_id, _ = _member(client)

    _assert_not_approved(
        client.post(
            "/v1/trainer/client-invites",
            json={"member_id": member_id},
            headers=_auth(trainer_token),
        )
    )
    assert (
        db_session.scalar(
            select(TrainerClientInvite).where(
                TrainerClientInvite.trainer_id == trainer_id
            )
        )
        is None
    )


def test_pending_trainer_can_still_use_profile_endpoints(client, db_session):
    """승인을 기다리는 동안 프로필을 채울 수 있어야 운영자가 판단할 수 있다."""
    gym = _gym(db_session)
    _, trainer_token = _sign_up_trainer(client, gym)

    updated = client.put(
        "/v1/trainer/me",
        headers=_auth(trainer_token),
        json={"specialty": "재활 트레이너", "career_years": 3},
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["verification"]["status"] == "pending"


# ---------------------------------------------------------------------------
# 승인
# ---------------------------------------------------------------------------


def test_approval_opens_directory_and_consultation(client, db_session):
    """가입 → 승인 → 목록 노출 → 상담 신청까지 한 줄로."""
    gym = _gym(db_session)
    trainer_id, trainer_token = _sign_up_trainer(client, gym)
    admin_id, admin_token = _admin(client, db_session)
    _, member_token = _member(client)

    approved = _approve(client, admin_token, trainer_id)
    assert approved.status_code == 200, approved.text
    body = approved.json()
    assert body["status"] == "approved"
    assert body["decided_by"] == admin_id
    assert body["decided_at"] is not None
    assert body["gym_is_fitness"] is True

    assert trainer_id in _directory_ids(client, member_token)
    assert trainer_id in _gym_trainer_ids(client, member_token, gym.id)
    detail = client.get(f"/v1/trainers/{trainer_id}", headers=_auth(member_token))
    assert detail.status_code == 200, detail.text

    consult = _request_consultation(client, member_token, trainer_id)
    assert consult.status_code == 201, consult.text

    me = client.get("/v1/trainer/me", headers=_auth(trainer_token))
    assert me.json()["verification"]["status"] == "approved"
    assert me.json()["verification"]["decided_at"] is not None


def test_approved_trainer_can_redeem_a_pairing_code(client, db_session):
    gym = _gym(db_session)
    trainer_id, trainer_token = _sign_up_trainer(client, gym)
    _, admin_token = _admin(client, db_session)
    member_id, member_token = _member(client)
    assert _approve(client, admin_token, trainer_id).status_code == 200

    redeemed = client.post(
        "/v1/trainer/pairing-code",
        json={"code": _issue_code(client, member_token)},
        headers=_auth(trainer_token),
    )
    assert redeemed.status_code == 200, redeemed.text
    assert redeemed.json()["member_id"] == member_id


def test_approval_is_audited(client, db_session):
    gym = _gym(db_session)
    trainer_id, _ = _sign_up_trainer(client, gym)
    admin_id, admin_token = _admin(client, db_session)

    assert _approve(client, admin_token, trainer_id).status_code == 200

    row = db_session.scalar(
        select(AuditLog).where(
            AuditLog.event == "admin.trainer_approve",
            AuditLog.user_id == admin_id,
            AuditLog.detail == trainer_id,
        )
    )
    assert row is not None


# ---------------------------------------------------------------------------
# 반려
# ---------------------------------------------------------------------------


def test_rejection_hides_trainer_and_shows_reason(client, db_session):
    gym = _gym(db_session)
    trainer_id, trainer_token = _sign_up_trainer(client, gym)
    _, admin_token = _admin(client, db_session)
    _, member_token = _member(client)

    rejected = _reject(client, admin_token, trainer_id, "  소속 확인이 되지 않았어요.  ")
    assert rejected.status_code == 200, rejected.text
    assert rejected.json()["status"] == "rejected"

    me = client.get("/v1/trainer/me", headers=_auth(trainer_token))
    assert me.json()["verification"]["status"] == "rejected"
    # 앞뒤 공백은 지운다 — 화면이 그대로 보여 준다.
    assert me.json()["verification"]["note"] == "소속 확인이 되지 않았어요."

    assert trainer_id not in _directory_ids(client, member_token)
    assert _request_consultation(client, member_token, trainer_id).status_code == 404
    _assert_not_approved(
        client.post(
            "/v1/trainer/pairing-code",
            json={"code": _issue_code(client, member_token)},
            headers=_auth(trainer_token),
        )
    )


def test_reapproval_clears_the_rejection_note(client, db_session):
    gym = _gym(db_session)
    trainer_id, trainer_token = _sign_up_trainer(client, gym)
    _, admin_token = _admin(client, db_session)

    assert _reject(client, admin_token, trainer_id, "서류 보완").status_code == 200
    assert _approve(client, admin_token, trainer_id).status_code == 200

    me = client.get("/v1/trainer/me", headers=_auth(trainer_token))
    assert me.json()["verification"]["status"] == "approved"
    assert me.json()["verification"]["note"] == ""


def test_invite_from_a_later_rejected_trainer_cannot_be_accepted(client, db_session):
    """승인 때 보낸 담당 요청이 반려 뒤에도 남아 있으면 그 수락이 기록을 연다."""
    gym = _gym(db_session)
    trainer_id, trainer_token = _sign_up_trainer(client, gym)
    _, admin_token = _admin(client, db_session)
    member_id, member_token = _member(client)
    assert _approve(client, admin_token, trainer_id).status_code == 200

    sent = client.post(
        "/v1/trainer/client-invites",
        json={"member_id": member_id},
        headers=_auth(trainer_token),
    )
    assert sent.status_code == 201, sent.text
    assert _reject(client, admin_token, trainer_id).status_code == 200

    accepted = client.post(
        f"/v1/me/coach/invites/{sent.json()['id']}/accept",
        json={"data_sharing_consent": True},
        headers=_auth(member_token),
    )
    assert accepted.status_code == 404, accepted.text
    assert (
        db_session.scalar(
            select(TrainerClient).where(
                TrainerClient.trainer_id == trainer_id,
                TrainerClient.member_id == member_id,
            )
        )
        is None
    )


# ---------------------------------------------------------------------------
# 관리자 전용
# ---------------------------------------------------------------------------


def test_admin_list_defaults_to_pending(client, db_session):
    gym = _gym(db_session)
    pending_id, _ = _sign_up_trainer(client, gym)
    seeded, _ = _seeded_trainer(db_session, gym)
    _, admin_token = _admin(client, db_session)

    pending = client.get("/v1/admin/trainers", headers=_auth(admin_token))
    assert pending.status_code == 200, pending.text
    ids = {row["trainer_id"] for row in pending.json()}
    assert pending_id in ids
    assert seeded.id not in ids

    everyone = client.get(
        "/v1/admin/trainers?status=all", headers=_auth(admin_token)
    )
    assert {pending_id, seeded.id} <= {row["trainer_id"] for row in everyone.json()}

    bad = client.get("/v1/admin/trainers?status=nope", headers=_auth(admin_token))
    assert bad.status_code == 422


def test_non_admins_cannot_decide(client, db_session):
    gym = _gym(db_session)
    trainer_id, trainer_token = _sign_up_trainer(client, gym)
    _, member_token = _member(client)

    for token in (member_token, trainer_token):
        assert _approve(client, token, trainer_id).status_code == 403
        assert _reject(client, token, trainer_id).status_code == 403
        listed = client.get("/v1/admin/trainers", headers=_auth(token))
        assert listed.status_code == 403

    unauthenticated = client.post(f"/v1/admin/trainers/{trainer_id}/approve")
    assert unauthenticated.status_code == 401

    profile = db_session.scalar(
        select(TrainerProfile).where(TrainerProfile.trainer_id == trainer_id)
    )
    db_session.refresh(profile)
    assert profile.verification_status == "pending"


def test_deciding_an_unknown_or_member_account_is_404(client, db_session):
    _, admin_token = _admin(client, db_session)
    member_id, _ = _member(client)

    assert _approve(client, admin_token, "no-such-trainer").status_code == 404
    assert _approve(client, admin_token, member_id).status_code == 404
    assert _reject(client, admin_token, member_id).status_code == 404
