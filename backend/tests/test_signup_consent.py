"""가입 동의 — 약관·개인정보·건강정보·만 14세 확인과 기록. (#2819)

앞부분은 DB 없이 도는 규칙·스키마 검사다. 뒤의 엔드포인트 검사는 `client`
픽스처를 쓰므로 DB 가 있는 환경(CI)에서 돈다.

확인하는 것:
- 가입 요청에 동의 목록을 실었다면 역할별 필수 항목이 모두 있어야 한다(422).
- 건강정보 동의는 회원만의 필수 항목이다 — 트레이너 가입은 요구하지 않는다.
- 동의는 항목·버전·시각으로 남고, 문서 버전이 오르면 다시 동의가 필요하다.
- 동의 목록 없이 만들어진 계정(옛 빌드·소셜 첫 가입)은 `consent_required` 로
  드러나고, `POST /users/me/consents` 로 채우면 풀린다.
"""
from __future__ import annotations

from datetime import datetime, timedelta
from uuid import uuid4

import pytest
from pydantic import ValidationError
from sqlalchemy import select

from app.core import clock
from app.models.models import User, UserConsent
from app.schemas.user import ConsentSubmit, TrainerRegister, UserRegister
from app.services import signup_consent
from app.services.social.base import SocialIdentity

PASSWORD = "consent-pw-1234"
MEMBER_REQUIRED = ["terms", "privacy", "health", "age14"]
TRAINER_REQUIRED = ["terms", "privacy", "age14"]

#: 고정 시각 — 기록 시각을 비교할 때 `clock.now()` 대신 넣는다.
FIXED_NOW = datetime(2026, 10, 1, 9, 30, tzinfo=clock.SEOUL)


def _email(tag: str) -> str:
    return f"consent-{tag}-{uuid4().hex[:8]}@oncare.com"


# ---- 규칙 (DB 불필요) ----


def test_member_requires_health_and_age_but_not_marketing():
    assert signup_consent.required_for("member") == frozenset(MEMBER_REQUIRED)
    assert "marketing" not in signup_consent.required_for("member")


def test_trainer_does_not_require_health_consent():
    assert signup_consent.required_for("trainer") == frozenset(TRAINER_REQUIRED)
    assert "health" not in signup_consent.required_for("trainer")


def test_unknown_role_falls_back_to_member_requirements():
    assert signup_consent.required_for("admin") == signup_consent.required_for(
        "member"
    )


def test_missing_required_lists_absent_items_sorted():
    assert signup_consent.missing_required("member", ["terms", "marketing"]) == [
        "age14",
        "health",
        "privacy",
    ]
    assert signup_consent.missing_required("member", MEMBER_REQUIRED) == []
    assert signup_consent.missing_required("trainer", TRAINER_REQUIRED) == []


def test_every_kind_has_a_current_version():
    for kind in signup_consent.ALL_KINDS:
        assert signup_consent.CURRENT_VERSIONS[kind]


def test_marketing_is_retired_and_no_longer_versioned():
    """마케팅 수신 동의는 더는 받지 않는다(#3007) — 기록할 버전도 없다."""
    assert "marketing" not in signup_consent.ALL_KINDS
    assert "marketing" in signup_consent.RETIRED_KINDS
    assert "marketing" not in signup_consent.CURRENT_VERSIONS


def test_every_received_kind_is_required_for_someone():
    """받는 항목 가운데 어느 역할에도 필수가 아닌 것(=선택)이 없다."""
    required = set().union(*signup_consent.REQUIRED_BY_ROLE.values())
    assert set(signup_consent.ALL_KINDS) == required


def test_missing_required_ignores_retired_marketing():
    with_mkt = [*MEMBER_REQUIRED, "marketing"]
    assert signup_consent.missing_required("member", with_mkt) == []
    assert signup_consent.missing_required("trainer", [*TRAINER_REQUIRED, "marketing"]) == []


# ---- 스키마 (DB 불필요) ----


def _register_body(**extra):
    return {"email": "schema@oncare.com", "password": PASSWORD, **extra}


def test_register_without_consent_list_is_accepted():
    """옛 빌드는 목록을 보내지 않는다 — 가입은 되고 로그인 뒤 동의 화면을 거친다."""
    assert UserRegister(**_register_body()).consents is None


def test_register_with_all_member_items_is_accepted():
    body = UserRegister(**_register_body(consents=MEMBER_REQUIRED))
    assert set(body.consents or []) == set(MEMBER_REQUIRED)


def test_register_from_old_build_with_marketing_is_still_accepted():
    """옛 빌드는 더는 받지 않는 마케팅 항목을 함께 보낸다(#3007) — 막지 않는다."""
    body = UserRegister(**_register_body(consents=[*MEMBER_REQUIRED, "marketing"]))
    assert "marketing" in (body.consents or [])


def test_trainer_register_from_old_build_with_marketing_is_still_accepted():
    body = TrainerRegister(**_register_body(consents=[*TRAINER_REQUIRED, "marketing"]))
    assert "marketing" in (body.consents or [])


def test_consent_submit_from_old_build_with_marketing_is_accepted():
    body = ConsentSubmit(consents=[*MEMBER_REQUIRED, "marketing"])
    assert "marketing" in body.consents


@pytest.mark.parametrize("dropped", MEMBER_REQUIRED)
def test_register_missing_one_member_item_is_rejected(dropped):
    kinds = [k for k in MEMBER_REQUIRED if k != dropped]
    with pytest.raises(ValidationError):
        UserRegister(**_register_body(consents=kinds))


def test_register_with_empty_list_is_rejected():
    """빈 목록은 '보냈지만 아무것도 체크하지 않았다'다 — 옛 빌드와 다르다."""
    with pytest.raises(ValidationError):
        UserRegister(**_register_body(consents=[]))


def test_register_unknown_item_is_rejected():
    with pytest.raises(ValidationError):
        UserRegister(**_register_body(consents=[*MEMBER_REQUIRED, "overseas"]))


def test_trainer_register_accepts_without_health():
    body = TrainerRegister(**_register_body(consents=TRAINER_REQUIRED))
    assert "health" not in (body.consents or [])


@pytest.mark.parametrize("dropped", TRAINER_REQUIRED)
def test_trainer_register_missing_one_item_is_rejected(dropped):
    kinds = [k for k in TRAINER_REQUIRED if k != dropped]
    with pytest.raises(ValidationError):
        TrainerRegister(**_register_body(consents=kinds))


def test_consent_submit_rejects_unknown_item():
    with pytest.raises(ValidationError):
        ConsentSubmit(consents=["terms", "newsletter"])


# ---- 회원 가입 ----


def _login(client, email: str) -> dict:
    r = client.post("/v1/auth/login", data={"username": email, "password": PASSWORD})
    assert r.status_code == 200, r.text
    return r.json()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_member_register_records_each_item_with_version(client, db_session):
    email = _email("member")
    r = client.post(
        "/v1/auth/register",
        json={
            "email": email,
            "password": PASSWORD,
            "name": "동의회원",
            "consents": MEMBER_REQUIRED,
        },
    )
    assert r.status_code == 201, r.text
    user_id = r.json()["id"]

    rows = db_session.scalars(
        select(UserConsent).where(UserConsent.user_id == user_id)
    ).all()
    assert {row.kind for row in rows} == set(MEMBER_REQUIRED)
    for row in rows:
        assert row.version == signup_consent.CURRENT_VERSIONS[row.kind]
        assert row.agreed_at is not None
        assert row.revoked_at is None


def test_member_register_with_retired_marketing_records_only_required(
    client, db_session
):
    """옛 빌드가 마케팅을 실어 보내도 가입은 되고, 마케팅 행은 남지 않는다(#3007)."""
    email = _email("nomkt")
    r = client.post(
        "/v1/auth/register",
        json={
            "email": email,
            "password": PASSWORD,
            "consents": [*MEMBER_REQUIRED, "marketing"],
        },
    )
    assert r.status_code == 201, r.text
    kinds = set(
        db_session.scalars(
            select(UserConsent.kind).where(UserConsent.user_id == r.json()["id"])
        )
    )
    assert kinds == set(MEMBER_REQUIRED)


def test_member_register_missing_health_is_422_and_creates_no_account(
    client, db_session
):
    email = _email("nohealth")
    r = client.post(
        "/v1/auth/register",
        json={
            "email": email,
            "password": PASSWORD,
            "consents": ["terms", "privacy", "age14"],
        },
    )
    assert r.status_code == 422, r.text
    assert db_session.scalar(select(User).where(User.email == email)) is None


def test_member_register_missing_age_check_is_422(client):
    r = client.post(
        "/v1/auth/register",
        json={
            "email": _email("noage"),
            "password": PASSWORD,
            "consents": ["terms", "privacy", "health"],
        },
    )
    assert r.status_code == 422, r.text


def test_consented_member_is_not_asked_again(client):
    email = _email("done")
    client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "consents": MEMBER_REQUIRED},
    )
    tokens = _login(client, email)
    assert tokens["consent_required"] is False

    me = client.get("/v1/users/me", headers=_auth(tokens["access_token"]))
    assert me.status_code == 200
    assert me.json()["consent_required"] is False
    assert me.json()["consent_pending"] == []


# ---- 동의 기록이 없는 기존 계정 ----


def test_account_without_consents_is_flagged_on_login_and_me(client):
    """동의 절차 이전에 가입한 계정과 같은 상태 — 목록 없이 만든다."""
    email = _email("legacy")
    client.post("/v1/auth/register", json={"email": email, "password": PASSWORD})

    tokens = _login(client, email)
    assert tokens["consent_required"] is True

    me = client.get("/v1/users/me", headers=_auth(tokens["access_token"])).json()
    assert me["consent_required"] is True
    assert me["consent_pending"] == sorted(MEMBER_REQUIRED)


def test_submitting_consents_clears_the_flag(client, db_session):
    email = _email("reconsent")
    reg = client.post("/v1/auth/register", json={"email": email, "password": PASSWORD})
    token = _login(client, email)["access_token"]

    r = client.post(
        "/v1/users/me/consents",
        json={"consents": MEMBER_REQUIRED},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    assert r.json() == {"consent_required": False, "consent_pending": []}

    assert client.get("/v1/users/me", headers=_auth(token)).json()[
        "consent_required"
    ] is False
    assert _login(client, email)["consent_required"] is False
    kinds = set(
        db_session.scalars(
            select(UserConsent.kind).where(UserConsent.user_id == reg.json()["id"])
        )
    )
    assert kinds == set(MEMBER_REQUIRED)


def test_submitting_partial_consents_is_422_and_records_nothing(client, db_session):
    email = _email("partial")
    reg = client.post("/v1/auth/register", json={"email": email, "password": PASSWORD})
    token = _login(client, email)["access_token"]

    r = client.post(
        "/v1/users/me/consents",
        json={"consents": ["terms", "privacy"]},
        headers=_auth(token),
    )
    assert r.status_code == 422
    assert r.json()["detail"]["code"] == "consent_required"
    assert r.json()["detail"]["missing"] == ["age14", "health"]
    assert (
        db_session.scalar(
            select(UserConsent).where(UserConsent.user_id == reg.json()["id"])
        )
        is None
    )


def test_submitting_consents_needs_a_token(client):
    r = client.post("/v1/users/me/consents", json={"consents": MEMBER_REQUIRED})
    assert r.status_code == 401


def test_submitting_twice_keeps_the_first_agreement_time(client, db_session):
    email = _email("twice")
    reg = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "consents": MEMBER_REQUIRED},
    )
    token = _login(client, email)["access_token"]
    user_id = reg.json()["id"]
    first = {
        row.kind: row.agreed_at
        for row in db_session.scalars(
            select(UserConsent).where(UserConsent.user_id == user_id)
        )
    }

    r = client.post(
        "/v1/users/me/consents",
        json={"consents": [*MEMBER_REQUIRED, "marketing"]},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text

    db_session.expire_all()
    rows = db_session.scalars(
        select(UserConsent).where(UserConsent.user_id == user_id)
    ).all()
    # 필수 항목은 다시 쓰지 않고, 옛 빌드가 실어 보낸 마케팅은 남기지 않는다(#3007).
    assert len(rows) == len(MEMBER_REQUIRED)
    assert "marketing" not in {row.kind for row in rows}
    for row in rows:
        if row.kind in first:
            assert row.agreed_at == first[row.kind]


# ---- 문서 버전 ----


def test_bumping_a_document_version_asks_again(client, db_session, monkeypatch):
    email = _email("version")
    reg = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "consents": MEMBER_REQUIRED},
    )
    user = db_session.get(User, reg.json()["id"])
    assert signup_consent.pending_kinds(db_session, user) == []

    bumped = {**signup_consent.CURRENT_VERSIONS, "privacy": "2099-01-01"}
    monkeypatch.setattr(signup_consent, "CURRENT_VERSIONS", bumped)

    assert signup_consent.pending_kinds(db_session, user) == ["privacy"]
    assert _login(client, email)["consent_required"] is True


def test_record_uses_the_given_time(client, db_session):
    email = _email("clock")
    reg = client.post("/v1/auth/register", json={"email": email, "password": PASSWORD})
    user_id = reg.json()["id"]

    signup_consent.record(db_session, user_id, ["terms"], now=FIXED_NOW)
    db_session.commit()

    row = db_session.scalar(
        select(UserConsent).where(
            UserConsent.user_id == user_id, UserConsent.kind == "terms"
        )
    )
    assert row is not None
    assert row.agreed_at == FIXED_NOW


def test_revoked_consent_counts_as_missing(client, db_session):
    email = _email("revoked")
    reg = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "consents": MEMBER_REQUIRED},
    )
    user = db_session.get(User, reg.json()["id"])
    row = db_session.scalar(
        select(UserConsent).where(
            UserConsent.user_id == user.id, UserConsent.kind == "health"
        )
    )
    row.revoked_at = FIXED_NOW
    db_session.commit()

    assert signup_consent.pending_kinds(db_session, user) == ["health"]


def test_consenting_again_after_revoking_revives_the_row(client, db_session):
    """철회한 동의를 같은 버전으로 다시 받으면 고유 제약에 걸리지 않고 되살린다."""
    email = _email("reconsent")
    reg = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "consents": MEMBER_REQUIRED},
    )
    user = db_session.get(User, reg.json()["id"])
    row = db_session.scalar(
        select(UserConsent).where(
            UserConsent.user_id == user.id, UserConsent.kind == "health"
        )
    )
    row.revoked_at = FIXED_NOW
    db_session.commit()

    later = FIXED_NOW + timedelta(days=1)
    signup_consent.record(db_session, user.id, ["health"], now=later)
    db_session.commit()

    rows = db_session.scalars(
        select(UserConsent).where(
            UserConsent.user_id == user.id, UserConsent.kind == "health"
        )
    ).all()
    assert len(rows) == 1
    assert rows[0].revoked_at is None
    assert rows[0].agreed_at == later
    assert signup_consent.pending_kinds(db_session, user) == []


def test_demo_consent_seed_survives_a_revoked_demo_consent(client, db_session):
    """데모 계정이 동의를 철회해 둔 상태에서 시드를 다시 돌려도 멈추지 않는다."""
    from app.db import init_db

    email = _email("seed-revoked")
    reg = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "consents": MEMBER_REQUIRED},
    )
    user = db_session.get(User, reg.json()["id"])
    row = db_session.scalar(
        select(UserConsent).where(
            UserConsent.user_id == user.id, UserConsent.kind == "privacy"
        )
    )
    row.revoked_at = FIXED_NOW
    db_session.commit()

    init_db._seed_demo_consents()

    db_session.expire_all()
    assert signup_consent.pending_kinds(db_session, user) == []


def test_consents_are_deleted_with_the_account(client, db_session):
    email = _email("withdraw")
    reg = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "consents": MEMBER_REQUIRED},
    )
    user_id = reg.json()["id"]
    token = _login(client, email)["access_token"]

    assert client.delete("/v1/users/me", headers=_auth(token)).status_code == 200

    db_session.expire_all()
    assert (
        db_session.scalar(select(UserConsent).where(UserConsent.user_id == user_id))
        is None
    )


# ---- 트레이너 가입 ----


def test_trainer_register_records_without_health(client, db_session):
    email = _email("trainer")
    r = client.post(
        "/v1/auth/trainer/register",
        json={
            "email": email,
            "password": PASSWORD,
            "name": "동의트레이너",
            "consents": TRAINER_REQUIRED,
        },
    )
    assert r.status_code == 201, r.text
    kinds = set(
        db_session.scalars(
            select(UserConsent.kind).where(UserConsent.user_id == r.json()["id"])
        )
    )
    assert kinds == set(TRAINER_REQUIRED)
    assert _login(client, email)["consent_required"] is False


def test_trainer_register_missing_age_check_is_422(client, db_session):
    email = _email("trainer-noage")
    r = client.post(
        "/v1/auth/trainer/register",
        json={"email": email, "password": PASSWORD, "consents": ["terms", "privacy"]},
    )
    assert r.status_code == 422, r.text
    assert db_session.scalar(select(User).where(User.email == email)) is None


def test_trainer_without_consents_reconsents_without_health(client):
    email = _email("trainer-legacy")
    client.post("/v1/auth/trainer/register", json={"email": email, "password": PASSWORD})
    tokens = _login(client, email)
    assert tokens["consent_required"] is True

    # `GET /users/me` 는 회원 전용이라 트레이너는 403 이다 — 트레이너 웹은 로그인
    # 응답의 `consent_required` 로 동의 화면을 띄우고, 남은 항목은 저장 응답으로 안다.
    # 필수 항목이 빠진 저장의 422 가 트레이너에게 요구하는 항목을 알려 준다.
    partial = client.post(
        "/v1/users/me/consents",
        json={"consents": ["terms"]},
        headers=_auth(tokens["access_token"]),
    )
    assert partial.status_code == 422, partial.text
    assert partial.json()["detail"]["missing"] == ["age14", "privacy"]

    r = client.post(
        "/v1/users/me/consents",
        json={"consents": TRAINER_REQUIRED},
        headers=_auth(tokens["access_token"]),
    )
    assert r.status_code == 200, r.text
    assert r.json()["consent_required"] is False
    assert r.json()["consent_pending"] == []


# ---- 소셜 첫 가입 ----


class _FakeVerifier:
    def __init__(self, identity: SocialIdentity) -> None:
        self._identity = identity

    async def verify(self, token: str) -> SocialIdentity:
        return self._identity


def test_first_social_login_must_go_through_consent(client, monkeypatch):
    """소셜 첫 가입은 가입 화면을 거치지 않는다 — 로그인 응답이 동의를 요구한다."""
    from app.api.v1 import social

    identity = SocialIdentity(
        provider="kakao",
        provider_user_id=f"consent-{uuid4().hex[:10]}",
        email=_email("social"),
        name="소셜회원",
    )
    monkeypatch.setattr(social, "get_verifier", lambda provider: _FakeVerifier(identity))

    first = client.post("/v1/auth/social/kakao", json={"token": "fake"})
    assert first.status_code == 200, first.text
    assert first.json()["consent_required"] is True

    token = first.json()["access_token"]
    r = client.post(
        "/v1/users/me/consents",
        json={"consents": MEMBER_REQUIRED},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text

    again = client.post("/v1/auth/social/kakao", json={"token": "fake"})
    assert again.json()["consent_required"] is False


# ---- 데모 계정 시드 ----


def test_seeded_demo_accounts_need_no_consent_screen(client, db_session):
    """데모 회원·트레이너는 시드가 필수 동의를 남겨 로그인 뒤 바로 쓸 수 있다."""
    from app.db.init_db import DEMO_USER_ID

    member = db_session.get(User, DEMO_USER_ID)
    trainer = db_session.scalar(select(User).where(User.email == "trainer@oncare.com"))
    assert member is not None and trainer is not None
    assert signup_consent.pending_kinds(db_session, member) == []
    assert signup_consent.pending_kinds(db_session, trainer) == []


def test_demo_consent_seed_leaves_real_accounts_alone(client, db_session):
    """데모 도메인이 아닌 계정에는 동의를 대신 남기지 않는다."""
    from app.db import init_db

    email = f"consent-real-{uuid4().hex[:8]}@example.com"
    res = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "name": "실사용자"},
    )
    assert res.status_code == 201, res.text

    init_db._seed_demo_consents()

    db_session.expire_all()
    user = db_session.scalar(select(User).where(User.email == email))
    assert signup_consent.pending_kinds(db_session, user) == sorted(MEMBER_REQUIRED)


# ---- 더는 받지 않는 마케팅 동의 (#3007) ----


def test_record_drops_retired_marketing(client, db_session):
    email = _email("record-mkt")
    reg = client.post("/v1/auth/register", json={"email": email, "password": PASSWORD})
    user_id = reg.json()["id"]

    signup_consent.record(db_session, user_id, [*MEMBER_REQUIRED, "marketing"])
    db_session.commit()

    kinds = set(
        db_session.scalars(select(UserConsent.kind).where(UserConsent.user_id == user_id))
    )
    assert kinds == set(MEMBER_REQUIRED)


def test_trainer_register_with_retired_marketing_records_only_required(
    client, db_session
):
    email = _email("trainer-mkt")
    r = client.post(
        "/v1/auth/trainer/register",
        json={
            "email": email,
            "password": PASSWORD,
            "name": "옛빌드트레이너",
            "consents": [*TRAINER_REQUIRED, "marketing"],
        },
    )
    assert r.status_code == 201, r.text
    kinds = set(
        db_session.scalars(
            select(UserConsent.kind).where(UserConsent.user_id == r.json()["id"])
        )
    )
    assert kinds == set(TRAINER_REQUIRED)


def test_old_marketing_row_does_not_affect_consent_status(client, db_session):
    """예전에 남은 마케팅 행은 동의 상태 계산에 끼지 않는다."""
    email = _email("old-mkt")
    reg = client.post(
        "/v1/auth/register",
        json={"email": email, "password": PASSWORD, "consents": MEMBER_REQUIRED},
    )
    user_id = reg.json()["id"]
    db_session.add(
        UserConsent(
            user_id=user_id,
            kind="marketing",
            version="2026-10-01",
            agreed_at=FIXED_NOW,
        )
    )
    db_session.commit()

    assert "marketing" not in signup_consent.agreed_kinds(db_session, user_id)
    me = client.get("/v1/users/me", headers=_auth(_login(client, email)["access_token"]))
    assert me.status_code == 200, me.text
    assert me.json()["consent_required"] is False
    assert "marketing" not in me.json()["consent_pending"]
