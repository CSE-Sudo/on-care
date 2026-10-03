"""트레이너 운영자 승인 절차 없음. (#3008)

트레이너는 가입하고 실재하는 헬스장을 고르면 바로 활동한다. 예전 승인 게이트(#2825)
네 자리 — 디렉터리(목록·추천·상세), 상담 대상, 담당 요청, 연결 코드 — 가 가입
직후부터 열려 있다. 사후 관리는 회원 신고와 운영자의 계정 정지다.

여기서 보는 것:

  * 가입 → 소속 선택만으로 디렉터리·헬스장 트레이너 목록·상세에 나온다.
  * 바로 상담 대상이 되고, 연결 코드와 담당 요청(회원 수락)으로 회원을 연결한다.
  * `/trainer/me` 에 승인 상태가 없고, 승인·반려 관리자 경로도 없다.
  * 예전 대기·반려 값이 남아 있어도 아무것도 가르지 않는다.
  * 0145 가 남은 대기·반려를 승인으로 채우고 DB 기본값을 승인으로 바꾼다.

다른 신고·정지 테스트가 이 파일의 도우미와 정리 픽스처를 함께 쓴다.

DB 가 필요하므로 로컬에서는 skip 되고 CI(Postgres) 에서 실행된다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core.security import hash_password
from app.models.models import (
    ConsultationRequest,
    MemberGym,
    MemberPairingCode,
    Notification,
    Place,
    TrainerClient,
    TrainerClientInvite,
    TrainerProfile,
    TrainerReport,
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
        db_session.query(TrainerReport).filter(
            (TrainerReport.trainer_id.in_(user_ids))
            | (TrainerReport.reporter_id.in_(user_ids))
        ).delete(synchronize_session=False)
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
        name="가입 테스트 헬스장",
        category="fitness",
        address="서울",
    )
    db_session.add(place)
    db_session.commit()
    return place


def _sign_up_trainer(client, gym: Place) -> tuple[str, str]:
    """공개 가입 → 소속 선택. (id, token) — 승인 없이 이것으로 끝난다."""
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
    """운영자가 직접 넣은 트레이너(ORM 기본값 경로). (user, email)"""
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
        json={"email": email, "password": PASSWORD, "name": "가입 회원"},
    )
    assert response.status_code == 201, response.text
    return response.json()["id"], _login(client, email)


def _admin(client, db_session) -> tuple[str, str]:
    """관리자 하나. 운영자 판별은 `users.is_admin` 이다."""
    member_id, _ = _member(client)
    user = db_session.get(User, member_id)
    user.is_admin = True
    db_session.commit()
    return member_id, _login(client, user.email)


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


# ---------------------------------------------------------------------------
# 가입 직후 — 승인 없이 열림
# ---------------------------------------------------------------------------


def test_signed_up_trainer_is_listed_right_away(client, db_session):
    gym = _gym(db_session)
    trainer_id, _ = _sign_up_trainer(client, gym)
    _, member_token = _member(client)

    assert trainer_id in _directory_ids(client, member_token)
    assert trainer_id in _gym_trainer_ids(client, member_token, gym.id)
    detail = client.get(f"/v1/trainers/{trainer_id}", headers=_auth(member_token))
    assert detail.status_code == 200, detail.text


def test_signed_up_trainer_takes_consultations_right_away(client, db_session):
    gym = _gym(db_session)
    trainer_id, _ = _sign_up_trainer(client, gym)
    _, member_token = _member(client)

    response = _request_consultation(client, member_token, trainer_id)
    assert response.status_code == 201, response.text


def test_signed_up_trainer_can_redeem_a_pairing_code(client, db_session):
    gym = _gym(db_session)
    _, trainer_token = _sign_up_trainer(client, gym)
    member_id, member_token = _member(client)
    code = _issue_code(client, member_token)

    preview = client.post(
        "/v1/trainer/pairing-code/preview",
        json={"code": code},
        headers=_auth(trainer_token),
    )
    assert preview.status_code == 200, preview.text
    redeemed = client.post(
        "/v1/trainer/pairing-code", json={"code": code}, headers=_auth(trainer_token)
    )
    assert redeemed.status_code == 200, redeemed.text
    assert redeemed.json()["member_id"] == member_id


def test_signed_up_trainer_connects_only_after_the_member_accepts(client, db_session):
    """담당 요청은 바로 보낼 수 있지만, 담당은 회원이 수락해야 생긴다."""
    gym = _gym(db_session)
    trainer_id, trainer_token = _sign_up_trainer(client, gym)
    member_id, member_token = _member(client)

    sent = client.post(
        "/v1/trainer/client-invites",
        json={"member_id": member_id},
        headers=_auth(trainer_token),
    )
    assert sent.status_code == 201, sent.text
    assert (
        db_session.scalar(
            select(TrainerClient).where(
                TrainerClient.trainer_id == trainer_id,
                TrainerClient.member_id == member_id,
            )
        )
        is None
    )

    accepted = client.post(
        f"/v1/me/coach/invites/{sent.json()['id']}/accept",
        json={"data_sharing_consent": True},
        headers=_auth(member_token),
    )
    assert accepted.status_code == 200, accepted.text
    db_session.expire_all()
    link = db_session.scalar(
        select(TrainerClient).where(
            TrainerClient.trainer_id == trainer_id,
            TrainerClient.member_id == member_id,
        )
    )
    assert link is not None and link.active is True


def test_trainer_without_a_gym_is_still_hidden(client, db_session):
    """승인은 없어졌지만 소속 헬스장 조건은 그대로다 — 헬스장이 트레이너를 묶는다."""
    email = f"{EMAIL_PREFIX}nogym-{uuid4().hex[:10]}@oncare.com"
    response = client.post(
        "/v1/auth/trainer/register",
        json={"email": email, "password": PASSWORD, "name": "소속 없음"},
    )
    assert response.status_code == 201, response.text
    _, member_token = _member(client)

    assert response.json()["id"] not in _directory_ids(client, member_token)


def test_signup_profile_is_stored_as_approved(client, db_session):
    gym = _gym(db_session)
    trainer_id, _ = _sign_up_trainer(client, gym)

    profile = db_session.scalar(
        select(TrainerProfile).where(TrainerProfile.trainer_id == trainer_id)
    )
    assert profile.verification_status == "approved"


def test_trainer_me_has_no_verification_state(client, db_session):
    gym = _gym(db_session)
    _, token = _sign_up_trainer(client, gym)

    me = client.get("/v1/trainer/me", headers=_auth(token))
    assert me.status_code == 200, me.text
    assert "verification" not in me.json()
    assert me.json()["is_admin"] is False


def test_trainer_me_marks_an_admin_trainer(client, db_session):
    gym = _gym(db_session)
    trainer, email = _seeded_trainer(db_session, gym)
    user = db_session.get(User, trainer.id)
    user.is_admin = True
    db_session.commit()

    me = client.get("/v1/trainer/me", headers=_auth(_login(client, email)))
    assert me.status_code == 200, me.text
    assert me.json()["is_admin"] is True


def test_leftover_pending_or_rejected_value_gates_nothing(client, db_session):
    """예전 값이 남은 행도 노출·상담·연결이 그대로 된다."""
    gym = _gym(db_session)
    for leftover in ("pending", "rejected"):
        trainer, email = _seeded_trainer(db_session, gym)
        profile = db_session.scalar(
            select(TrainerProfile).where(TrainerProfile.trainer_id == trainer.id)
        )
        profile.verification_status = leftover
        db_session.commit()
        _, member_token = _member(client)

        assert trainer.id in _directory_ids(client, member_token)
        assert (
            _request_consultation(client, member_token, trainer.id).status_code
            == 201
        )
        redeemed = client.post(
            "/v1/trainer/pairing-code",
            json={"code": _issue_code(client, member_token)},
            headers=_auth(_login(client, email)),
        )
        assert redeemed.status_code == 200, redeemed.text


def test_approval_endpoints_are_gone(client, db_session):
    gym = _gym(db_session)
    trainer_id, _ = _sign_up_trainer(client, gym)
    _, admin_token = _admin(client, db_session)

    for action in ("approve", "reject"):
        response = client.post(
            f"/v1/admin/trainers/{trainer_id}/{action}",
            headers=_auth(admin_token),
            json={},
        )
        assert response.status_code in (404, 405), response.text


# ---------------------------------------------------------------------------
# 0145 마이그레이션
# ---------------------------------------------------------------------------


def _migration_0145():
    import importlib.util
    from pathlib import Path

    path = (
        Path(__file__).resolve().parents[1]
        / "migrations/versions/0145_trainer_reports_no_approval.py"
    )
    spec = importlib.util.spec_from_file_location("m0145", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module, path.read_text(encoding="utf-8")


def test_migration_backfills_before_changing_the_default():
    module, source = _migration_0145()
    assert module.revision == "0145_trainer_reports_no_approval"
    upgrade = source[source.index("def upgrade"): source.index("def downgrade")]
    assert "verification_status = 'approved'" in upgrade
    assert upgrade.index("UPDATE trainer_profiles") < upgrade.index(
        'server_default="approved"'
    )
    # 승인 칸은 지우지 않는다.
    assert "drop_column" not in upgrade


def test_migration_0145_follows_0144_ai_call_usages():
    """0140 → 0141 → 0142 → 0143 → 0144 → 0145 한 줄 체인의 끝이다 — head 하나."""
    module, source = _migration_0145()
    assert module.down_revision == "0144_ai_call_usages"
    assert "Revises: 0144_ai_call_usages" in source


def test_db_default_is_approved(client):
    """ORM 을 거치지 않고 들어온 행도 승인 상태다 — 0145 의 DB 기본값."""
    from sqlalchemy import inspect

    from app.db.session import engine

    columns = {c["name"]: c for c in inspect(engine).get_columns("trainer_profiles")}
    assert "approved" in str(columns["verification_status"]["default"])
