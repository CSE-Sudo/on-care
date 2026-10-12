"""아이디(가입 이메일) 찾기 `POST /auth/find-email`(#3337) — DB 필요(로컬 skip, CI 실행)."""
from __future__ import annotations

from collections.abc import Callable, Iterator
from uuid import uuid4

import pytest

from app.core.config import get_settings
from app.models import models

_PW = "find-pw-123"


def _phone() -> str:
    """테스트마다 다른 번호 — 시드·다른 테스트의 계정과 겹치지 않는다."""
    digits = f"{uuid4().int % 10**8:08d}"
    return f"010-{digits[:4]}-{digits[4:]}"


def _find(client, name: str, phone: str):
    return client.post("/v1/auth/find-email", json={"name": name, "phone": phone})


@pytest.fixture
def signup(client, db_session) -> Iterator[Callable[..., str]]:
    """회원을 가입시키고 이메일을 돌려준다. 끝나면 만든 계정을 지운다."""
    created: list[str] = []

    def _signup(name: str, phone: str, *, local: str | None = None) -> str:
        email = f"{local or 'fe' + uuid4().hex[:10]}@find-{uuid4().hex[:6]}.oncare.com"
        res = client.post(
            "/v1/auth/register",
            json={"email": email, "password": _PW, "name": name, "phone": phone},
        )
        assert res.status_code == 201, res.text
        created.append(res.json()["id"])
        return email

    yield _signup
    db_session.expire_all()
    for user_id in created:
        row = db_session.get(models.User, user_id)
        if row is not None:
            db_session.delete(row)
    db_session.commit()


def _user(db_session, email: str) -> models.User:
    db_session.expire_all()
    return db_session.query(models.User).filter(models.User.email == email).one()


# ---- 찾음 ----


def test_matching_name_and_phone_returns_masked_email(client, signup):
    phone = _phone()
    email = signup("김찾기", phone, local="honggildong")
    res = _find(client, "김찾기", phone)
    assert res.status_code == 200, res.text
    domain = email.split("@")[1]
    assert res.json() == {
        "accounts": [{"masked_email": f"ho***@{domain}", "providers": []}]
    }


def test_full_email_never_appears_in_response(client, signup):
    phone = _phone()
    email = signup("김찾기", phone, local="honggildong")
    res = _find(client, "김찾기", phone)
    assert email not in res.text
    assert "honggildong" not in res.text


def test_phone_is_normalized_like_signup(client, signup):
    """하이픈 없이 보내도 가입 때와 같은 표기로 맞춰 비교한다."""
    phone = _phone()
    signup("김찾기", phone)
    res = _find(client, "김찾기", phone.replace("-", ""))
    assert len(res.json()["accounts"]) == 1


def test_name_ignores_surrounding_space_and_case(client, signup):
    phone = _phone()
    signup("Kim Finder", phone)
    res = _find(client, "  kim finder ", phone)
    assert len(res.json()["accounts"]) == 1


def test_accounts_sharing_a_phone_are_all_returned_masked(client, signup):
    """전화번호에는 유일성 제약이 없다 — 같은 이름·번호의 계정은 모두 가려서 준다."""
    phone = _phone()
    first = signup("김찾기", phone, local="alpha")
    second = signup("김찾기", phone, local="bravo")
    res = _find(client, "김찾기", phone)
    assert [a["masked_email"] for a in res.json()["accounts"]] == [
        f"al***@{first.split('@')[1]}",
        f"br***@{second.split('@')[1]}",
    ]


# ---- 없음 ----


def test_unknown_person_gets_200_with_empty_list(client):
    res = _find(client, "없는사람", _phone())
    assert res.status_code == 200
    assert res.json() == {"accounts": []}


def test_wrong_name_for_a_known_phone_finds_nothing(client, signup):
    phone = _phone()
    signup("김찾기", phone)
    res = _find(client, "이찾기", phone)
    assert res.status_code == 200
    assert res.json() == {"accounts": []}


def test_right_name_with_another_phone_finds_nothing(client, signup):
    signup("김찾기", _phone())
    assert _find(client, "김찾기", _phone()).json() == {"accounts": []}


def test_inactive_account_is_not_found(client, db_session, signup):
    phone = _phone()
    email = signup("김찾기", phone)
    user = _user(db_session, email)
    user.is_active = False
    db_session.commit()
    assert _find(client, "김찾기", phone).json() == {"accounts": []}


def test_trainer_account_is_not_found(client, db_session, signup):
    """회원 계정만 찾는다 — 역할이 다른 계정은 같은 이름·번호여도 빠진다."""
    phone = _phone()
    email = signup("김찾기", phone)
    user = _user(db_session, email)
    user.role = "trainer"
    db_session.commit()
    assert _find(client, "김찾기", phone).json() == {"accounts": []}


# ---- 소셜 가입 ----


def _link_social(db_session, user: models.User, provider: str) -> None:
    db_session.add(
        models.SocialAccount(
            user_id=user.id, provider=provider, provider_user_id=uuid4().hex
        )
    )
    db_session.commit()


def test_social_only_account_returns_provider_without_email(
    client, db_session, signup
):
    phone = _phone()
    email = signup("김소셜", phone, local="socialperson")
    user = _user(db_session, email)
    user.hashed_password = ""
    db_session.commit()
    _link_social(db_session, user, "kakao")
    res = _find(client, "김소셜", phone)
    assert res.json() == {"accounts": [{"masked_email": None, "providers": ["kakao"]}]}
    assert "socialperson" not in res.text


def test_placeholder_email_is_never_shown(client, db_session, signup):
    """확인된 이메일 없이 소셜로 가입한 계정의 대체 이메일은 가려서도 주지 않는다."""
    phone = _phone()
    email = signup("김소셜", phone)
    user = _user(db_session, email)
    user.email = f"kakao_{uuid4().hex[:10]}@social.oncare"
    db_session.commit()
    _link_social(db_session, user, "kakao")
    res = _find(client, "김소셜", phone)
    assert res.json() == {"accounts": [{"masked_email": None, "providers": ["kakao"]}]}
    assert "social.oncare" not in res.text


def test_password_account_with_linked_social_keeps_masked_email(
    client, db_session, signup
):
    phone = _phone()
    email = signup("김연결", phone, local="linked")
    _link_social(db_session, _user(db_session, email), "google")
    account = _find(client, "김연결", phone).json()["accounts"][0]
    assert account["masked_email"] == f"li***@{email.split('@')[1]}"
    assert account["providers"] == ["google"]


# ---- 입력 검사 ----


@pytest.mark.parametrize(
    "body",
    [
        {"name": "김찾기", "phone": ""},
        {"name": "김찾기", "phone": "0101234"},
        {"name": "김찾기", "phone": "011-1234-5678"},
        {"name": "", "phone": "010-1234-5678"},
        {"name": "   ", "phone": "010-1234-5678"},
        {"name": "김찾기"},
        {"phone": "010-1234-5678"},
    ],
)
def test_malformed_input_is_422(client, body):
    assert client.post("/v1/auth/find-email", json=body).status_code == 422


def test_blank_phone_does_not_match_accounts_without_phone(client, signup):
    """번호 없이 가입한 계정이 이름만으로 걸리지 않는다."""
    signup("번호없음", "")
    res = client.post("/v1/auth/find-email", json={"name": "번호없음", "phone": " "})
    assert res.status_code == 422


# ---- 시도 제한 ----


def test_per_phone_limit_blocks_repeated_attempts(client, monkeypatch, signup):
    monkeypatch.setattr(get_settings(), "find_email_phone_per_window", 2)
    phone = _phone()
    signup("김찾기", phone)
    assert _find(client, "김찾기", phone).status_code == 200
    assert _find(client, "이찾기", phone).status_code == 200
    blocked = _find(client, "박찾기", phone)
    assert blocked.status_code == 429
    assert "accounts" not in blocked.text


def test_per_phone_limit_counts_unknown_numbers_too(client, monkeypatch):
    """계정이 없는 번호도 똑같이 센다 — 429 로 가입 여부를 알 수 없다."""
    monkeypatch.setattr(get_settings(), "find_email_phone_per_window", 1)
    phone = _phone()
    assert _find(client, "없는사람", phone).status_code == 200
    assert _find(client, "없는사람", phone).status_code == 429


def test_per_phone_limit_ignores_phone_notation(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "find_email_phone_per_window", 1)
    phone = _phone()
    assert _find(client, "없는사람", phone).status_code == 200
    assert _find(client, "없는사람", phone.replace("-", "")).status_code == 429


def test_other_phones_are_not_blocked_by_one_phone_limit(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "find_email_phone_per_window", 1)
    first = _phone()
    assert _find(client, "없는사람", first).status_code == 200
    assert _find(client, "없는사람", first).status_code == 429
    assert _find(client, "없는사람", _phone()).status_code == 200


# ---- 감사 로그 ----


def test_audit_log_records_outcome_without_personal_data(client, db_session, signup):
    phone = _phone()
    signup("김찾기", phone)
    _find(client, "김찾기", phone)
    db_session.expire_all()
    row = (
        db_session.query(models.AuditLog)
        .filter(models.AuditLog.event == "auth.find_email")
        .order_by(models.AuditLog.id.desc())
        .first()
    )
    assert row is not None
    assert row.success is True
    assert phone not in (row.detail or "")
    assert "김찾기" not in (row.detail or "")
