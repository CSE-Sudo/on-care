"""위치정보 이용 동의 — 선택 동의 항목의 기록·조회·철회. (#3136)

회원 앱 헬스장 찾기는 기기의 현재 좌표를 받아 주변 검색에 쓴다. 위치기반서비스를
제공하려면 이용약관을 두고 이용자의 동의를 받아야 해서, 헬스장 찾기를 처음 쓸 때
동의를 받고 MY 에서 철회할 수 있게 했다. 가입 필수 항목이 아니다 — 위치 없이도
서비스 대부분을 쓸 수 있다.

확인하는 것:
- `location` 은 선택 항목이다. 어느 역할의 필수 판정에도 들지 않고, 가입·재동의
  화면의 `POST /users/me/consents` 로는 받지 않는다.
- 동의·철회가 버전·시각과 함께 남고, 동의하지 않아도 데이터 API 는 막히지 않는다.
- 약관 버전이 오르면 옛 버전에만 동의한 계정은 동의하지 않은 것으로 본다.
- 버전 날짜가 회원 앱 위치기반서비스 이용약관 부칙의 시행일과 같다.

앞부분은 DB 없이 돈다. 엔드포인트 검사는 `client` 픽스처를 쓰므로 DB 가 있는
환경(CI)에서 돈다.
"""
from __future__ import annotations

import json
import re
from datetime import date, datetime, timedelta
from pathlib import Path
from uuid import uuid4

import pytest
from pydantic import ValidationError
from sqlalchemy import select

from app.core import clock
from app.models.models import User, UserConsent
from app.schemas.user import ConsentSubmit, UserRegister
from app.services import signup_consent

PASSWORD = "location-pw-1234"
MEMBER_REQUIRED = ["terms", "privacy", "health", "age14"]
TRAINER_REQUIRED = ["terms", "privacy", "age14"]
PATH = "/v1/users/me/consents/location"

FIXED_NOW = datetime(2026, 10, 5, 9, 30, tzinfo=clock.SEOUL)

_ROOT = Path(__file__).resolve().parents[2]
_MEMBER_ARB = {
    lang: _ROOT / "frontend" / "flutter" / "lib" / "l10n" / f"app_{lang}.arb"
    for lang in ("ko", "en")
}


def _email(tag: str) -> str:
    return f"location-{tag}-{uuid4().hex[:8]}@oncare.com"


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _member(client, tag: str, consents: list[str] | None = None) -> tuple[str, str]:
    """필수 동의를 마친 회원을 만들어 (user_id, access_token) 을 돌려준다."""
    email = _email(tag)
    reg = client.post(
        "/v1/auth/register",
        json={
            "email": email,
            "password": PASSWORD,
            "consents": MEMBER_REQUIRED if consents is None else consents,
        },
    )
    assert reg.status_code == 201, reg.text
    login = client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    )
    assert login.status_code == 200, login.text
    return reg.json()["id"], login.json()["access_token"]


# ---- 규칙 (DB 불필요) ----


def test_location_is_an_optional_kind():
    assert signup_consent.LOCATION == "location"
    assert signup_consent.LOCATION in signup_consent.OPTIONAL_KINDS
    assert signup_consent.LOCATION not in signup_consent.ALL_KINDS


def test_location_is_required_for_no_role():
    """위치 없이도 서비스 대부분을 쓸 수 있다 — 필수 판정에 넣지 않는다."""
    for role, required in signup_consent.REQUIRED_BY_ROLE.items():
        assert signup_consent.LOCATION not in required, role
    assert signup_consent.missing_required("member", MEMBER_REQUIRED) == []
    assert signup_consent.missing_required("trainer", TRAINER_REQUIRED) == []


def test_location_has_a_current_version():
    version = signup_consent.CURRENT_VERSIONS[signup_consent.LOCATION]
    assert date.fromisoformat(version)


def test_optional_and_required_kinds_do_not_overlap():
    assert not set(signup_consent.OPTIONAL_KINDS) & set(signup_consent.ALL_KINDS)
    assert not set(signup_consent.OPTIONAL_KINDS) & set(signup_consent.RETIRED_KINDS)


def test_signup_consent_screen_does_not_take_location():
    """가입·재동의 화면의 저장은 필수 항목만 받는다 — 선택 동의는 따로 받는다."""
    with pytest.raises(ValidationError):
        ConsentSubmit(consents=[*MEMBER_REQUIRED, "location"])


def test_register_does_not_take_location():
    with pytest.raises(ValidationError):
        UserRegister(
            email="schema@oncare.com",
            password=PASSWORD,
            consents=[*MEMBER_REQUIRED, "location"],
        )


# ---- 약관 시행일과 버전 (DB 불필요) ----

_needs_arb = pytest.mark.skipif(
    not all(p.exists() for p in _MEMBER_ARB.values()),
    reason="프론트 소스가 없는 체크아웃",
)


def _location_terms(lang: str) -> dict[str, str]:
    data = json.loads(_MEMBER_ARB[lang].read_text(encoding="utf-8"))
    return {
        "title": data["myLegalLocationTitle"],
        "body": data["myLegalLocationBody"],
        "date": data["myLegalLocationEffectiveDate"],
    }


def _location_version() -> date:
    return date.fromisoformat(signup_consent.CURRENT_VERSIONS[signup_consent.LOCATION])


@_needs_arb
def test_korean_terms_take_effect_on_the_consent_version():
    found = re.findall(
        r"(\d{4})년 (\d{1,2})월 (\d{1,2})일부터 시행", _location_terms("ko")["body"]
    )
    assert len(found) == 1, "부칙의 시행일 줄이 하나여야 한다"
    y, m, d = (int(x) for x in found[0])
    assert date(y, m, d) == _location_version()


@_needs_arb
def test_english_terms_take_effect_on_the_consent_version():
    v = _location_version()
    body = _location_terms("en")["body"]
    month = v.strftime("%B")
    assert f"{v.day} {month} {v.year}" in body


@_needs_arb
def test_terms_header_date_is_the_consent_version():
    v = _location_version()
    assert _location_terms("ko")["date"] == f"시행일 {v:%Y. %m. %d.}"
    assert _location_terms("en")["date"] == f"Effective {v:%b} {v.day}, {v.year}"


@_needs_arb
def test_terms_cover_what_the_consent_sheet_promises():
    """동의 시트가 말하는 내용(목적·항목·보관·제공·철회)이 약관에도 있다."""
    ko = _location_terms("ko")["body"]
    for words in ("헬스장", "좌표", "저장하지 않", "카카오", "철회", "{contact}"):
        assert words in ko, words
    en = _location_terms("en")["body"]
    for words in ("gym", "coordinates", "not stored", "Kakao", "withdraw", "{contact}"):
        assert words in en, words


@_needs_arb
def test_english_terms_say_the_korean_original_governs():
    assert "Korean" in _location_terms("en")["body"]


# ---- 엔드포인트 ----


def test_member_who_never_answered_is_not_agreed(client):
    _, token = _member(client, "fresh")
    r = client.get(PATH, headers=_auth(token))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["kind"] == "location"
    assert body["agreed"] is False
    assert body["current_version"] == signup_consent.CURRENT_VERSIONS["location"]
    assert body["version"] is None
    assert body["agreed_at"] is None
    assert body["revoked_at"] is None


def test_agreeing_records_the_current_version_and_time(client, db_session):
    user_id, token = _member(client, "agree")
    r = client.put(PATH, headers=_auth(token))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["agreed"] is True
    assert body["version"] == signup_consent.CURRENT_VERSIONS["location"]
    assert body["agreed_at"] is not None
    assert body["revoked_at"] is None

    rows = db_session.scalars(
        select(UserConsent).where(
            UserConsent.user_id == user_id, UserConsent.kind == "location"
        )
    ).all()
    assert len(rows) == 1
    assert rows[0].version == signup_consent.CURRENT_VERSIONS["location"]
    assert rows[0].revoked_at is None


def test_agreeing_twice_keeps_the_first_time(client, db_session):
    user_id, token = _member(client, "twice")
    signup_consent.record(db_session, user_id, ["location"], now=FIXED_NOW)
    db_session.commit()

    r = client.put(PATH, headers=_auth(token))
    assert r.status_code == 200, r.text
    agreed_at = datetime.fromisoformat(r.json()["agreed_at"])
    assert agreed_at == FIXED_NOW

    count = len(
        db_session.scalars(
            select(UserConsent).where(
                UserConsent.user_id == user_id, UserConsent.kind == "location"
            )
        ).all()
    )
    assert count == 1


def test_revoking_keeps_the_row_and_records_the_time(client, db_session):
    user_id, token = _member(client, "revoke")
    assert client.put(PATH, headers=_auth(token)).status_code == 200

    r = client.delete(PATH, headers=_auth(token))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["agreed"] is False
    assert body["revoked_at"] is not None
    # 언제 동의했는지도 함께 남는다 — 행을 지우지 않는다.
    assert body["agreed_at"] is not None
    assert body["version"] == signup_consent.CURRENT_VERSIONS["location"]

    db_session.expire_all()
    row = db_session.scalar(
        select(UserConsent).where(
            UserConsent.user_id == user_id, UserConsent.kind == "location"
        )
    )
    assert row is not None
    assert row.revoked_at is not None

    assert client.get(PATH, headers=_auth(token)).json()["agreed"] is False


def test_revoking_without_a_record_is_harmless(client):
    _, token = _member(client, "norecord")
    r = client.delete(PATH, headers=_auth(token))
    assert r.status_code == 200, r.text
    assert r.json()["agreed"] is False
    assert r.json()["revoked_at"] is None
    # 같은 요청을 다시 보내도 결과가 같다.
    again = client.delete(PATH, headers=_auth(token))
    assert again.status_code == 200
    assert again.json() == r.json()


def test_agreeing_again_after_revoking_revives_the_row(client, db_session):
    user_id, token = _member(client, "revive")
    assert client.put(PATH, headers=_auth(token)).status_code == 200
    assert client.delete(PATH, headers=_auth(token)).status_code == 200

    r = client.put(PATH, headers=_auth(token))
    assert r.status_code == 200, r.text
    assert r.json()["agreed"] is True
    assert r.json()["revoked_at"] is None

    db_session.expire_all()
    rows = db_session.scalars(
        select(UserConsent).where(
            UserConsent.user_id == user_id, UserConsent.kind == "location"
        )
    ).all()
    assert len(rows) == 1
    assert rows[0].revoked_at is None


def test_location_does_not_change_required_consent(client, db_session):
    """동의해도, 철회해도 필수 동의 판정과 데이터 API 는 그대로다."""
    user_id, token = _member(client, "required")
    user = db_session.get(User, user_id)

    assert signup_consent.pending_kinds(db_session, user) == []
    assert client.put(PATH, headers=_auth(token)).status_code == 200
    assert signup_consent.pending_kinds(db_session, user) == []
    assert client.delete(PATH, headers=_auth(token)).status_code == 200
    assert signup_consent.pending_kinds(db_session, user) == []

    me = client.get("/v1/users/me", headers=_auth(token))
    assert me.status_code == 200
    assert me.json()["consent_required"] is False
    assert "location" not in me.json()["consent_pending"]
    # 위치 동의 없이도 회원 데이터 API 를 쓴다.
    assert client.get("/v1/users/me/health", headers=_auth(token)).status_code == 200


def test_bumping_the_terms_version_asks_again(client, db_session, monkeypatch):
    user_id, token = _member(client, "bump")
    agreed = client.put(PATH, headers=_auth(token)).json()
    assert agreed["agreed"] is True
    old_version = agreed["version"]

    monkeypatch.setitem(signup_consent.CURRENT_VERSIONS, "location", "2099-01-01")

    r = client.get(PATH, headers=_auth(token))
    assert r.status_code == 200
    body = r.json()
    assert body["agreed"] is False
    assert body["current_version"] == "2099-01-01"
    # 옛 버전에 동의했던 기록은 그대로 보인다.
    assert body["version"] == old_version

    # 새 버전에 다시 동의하면 새 행이 더해지고 옛 행은 남는다.
    again = client.put(PATH, headers=_auth(token))
    assert again.json()["agreed"] is True
    assert again.json()["version"] == "2099-01-01"
    versions = set(
        db_session.scalars(
            select(UserConsent.version).where(
                UserConsent.user_id == user_id, UserConsent.kind == "location"
            )
        )
    )
    assert "2099-01-01" in versions
    assert len(versions) == 2


def test_required_kinds_cannot_be_revoked_through_this_path(client):
    """필수 항목은 선택 동의 경로로 거두지 못한다 — 경로에서 422."""
    _, token = _member(client, "required-path")
    for kind in ("terms", "privacy", "health", "age14", "marketing", "unknown"):
        path = f"/v1/users/me/consents/{kind}"
        assert client.delete(path, headers=_auth(token)).status_code == 422, kind
        assert client.put(path, headers=_auth(token)).status_code == 422, kind
        assert client.get(path, headers=_auth(token)).status_code == 422, kind


def test_needs_a_token(client):
    assert client.get(PATH).status_code == 401
    assert client.put(PATH).status_code == 401
    assert client.delete(PATH).status_code == 401


def test_trainer_cannot_use_location_consent(client):
    """트레이너 웹은 위치를 쓰지 않는다 — 회원 전용 경로다."""
    email = _email("trainer")
    reg = client.post(
        "/v1/auth/trainer/register",
        json={"email": email, "password": PASSWORD, "consents": TRAINER_REQUIRED},
    )
    assert reg.status_code == 201, reg.text
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    ).json()["access_token"]
    assert client.get(PATH, headers=_auth(token)).status_code == 403
    assert client.put(PATH, headers=_auth(token)).status_code == 403


def test_member_without_required_consent_is_stopped_first(
    client, without_default_consent
):
    """필수 동의가 남은 회원은 선택 동의보다 필수 동의 화면이 먼저다(#3088)."""
    # 가입 화면에서 필수 동의를 마친 회원.
    _, token = _member(client, "pending")
    # 목록 없이 가입한 계정(옛 빌드·소셜 첫 가입과 같은 상태) — 필수 동의가 비어 있다.
    email = _email("legacy")
    client.post("/v1/auth/register", json={"email": email, "password": PASSWORD})
    legacy = client.post(
        "/v1/auth/login", data={"username": email, "password": PASSWORD}
    ).json()["access_token"]
    r = client.put(PATH, headers=_auth(legacy))
    assert r.status_code == 403, r.text
    assert r.json()["detail"]["code"] == "consent_required"
    # 필수 동의를 마친 회원은 그대로 쓴다.
    assert client.put(PATH, headers=_auth(token)).status_code == 200


def test_location_consents_are_deleted_with_the_account(client, db_session):
    user_id, token = _member(client, "withdraw")
    assert client.put(PATH, headers=_auth(token)).status_code == 200
    r = client.request(
        "DELETE",
        "/v1/users/me",
        json={"current_password": PASSWORD},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.text
    db_session.expire_all()
    left = db_session.scalars(
        select(UserConsent).where(UserConsent.user_id == user_id)
    ).all()
    assert left == []


def test_optional_state_prefers_the_latest_record(client, db_session):
    user_id, _ = _member(client, "latest")
    signup_consent.record(db_session, user_id, ["location"], now=FIXED_NOW)
    db_session.commit()
    later = FIXED_NOW + timedelta(hours=1)
    assert signup_consent.revoke(db_session, user_id, "location", now=later) is True
    db_session.commit()

    row = signup_consent.optional_state(db_session, user_id, "location")
    assert row is not None
    assert row.agreed_at == FIXED_NOW
    assert row.revoked_at == later
    assert signup_consent.is_agreed(db_session, user_id, "location") is False
    # 이미 철회했으면 다시 철회할 것이 없다.
    assert signup_consent.revoke(db_session, user_id, "location") is False
