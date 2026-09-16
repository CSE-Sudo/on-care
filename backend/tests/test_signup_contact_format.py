"""가입 이메일·전화번호의 서버 형식 검증. (#1780)

앞부분(`clean_email`/`normalize_phone`)은 DB 없이 도는 순수 검사다. 뒤의
엔드포인트 검사는 `client` 픽스처를 쓰므로 로컬에서는 skip 되고 CI 에서 돈다.

앱 가입 화면이 이미 형식을 거르지만, 그건 보내기 전 안내일 뿐이다. 여기서
확인하는 것은 **앱을 거치지 않은 요청**이 막히는가, 그리고 표기가 섞여 들어와도
한 가지 형태로 저장되는가다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest

from app.models.models import HealthProfile, User
from app.services.contact_format import (
    InvalidEmail,
    InvalidPhone,
    clean_email,
    normalize_phone,
)

EMAIL_PREFIX = "contact-format-"
PASSWORD = "contact-pw-1234"


# ---- 형식 규칙 (DB 불필요) ----


@pytest.mark.parametrize(
    "value",
    [
        "member@oncare.com",
        "  member@oncare.com  ",  # 앞뒤 공백은 잘라낸다
        "first.last+tag@sub.oncare.co.kr",
    ],
)
def test_clean_email_accepts_ordinary_addresses(value):
    assert clean_email(value) == value.strip()


@pytest.mark.parametrize(
    "value",
    [
        "",
        "   ",
        "member",  # 골뱅이 없음
        "member@",
        "@oncare.com",
        "member@oncare",  # 최상위 도메인 없음
        "mem ber@oncare.com",
        ".member@oncare.com",
        "member..name@oncare.com",
    ],
)
def test_clean_email_rejects_malformed(value):
    with pytest.raises(InvalidEmail):
        clean_email(value)


def test_clean_email_keeps_the_typed_value():
    """대소문자를 바꾸지 않는다 — 로그인 조회가 그대로 비교한다."""
    assert clean_email("Member@ONCARE.com") == "Member@ONCARE.com"


@pytest.mark.parametrize(
    ("value", "stored"),
    [
        ("010-1234-5678", "010-1234-5678"),
        ("01012345678", "010-1234-5678"),  # 하이픈 없이 보내도 같은 표기로
        (" 010 1234 5678 ", "010-1234-5678"),
        ("", ""),  # 전화번호는 선택이다
        ("   ", ""),
    ],
)
def test_normalize_phone_stores_one_shape(value, stored):
    assert normalize_phone(value) == stored


@pytest.mark.parametrize(
    "value",
    [
        "010-1234-567",  # 10 자리
        "010-1234-56789",  # 12 자리
        "0101234",
        "전화번호",
        "010-abcd-5678",
    ],
)
def test_normalize_phone_rejects_wrong_digit_count(value):
    with pytest.raises(InvalidPhone):
        normalize_phone(value)


# ---- 가입 엔드포인트 (DB 필요) ----


@pytest.fixture
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
        db_session.query(HealthProfile).filter(
            HealthProfile.user_id.in_(user_ids)
        ).delete(synchronize_session=False)
        db_session.query(User).filter(User.id.in_(user_ids)).delete(
            synchronize_session=False
        )
    db_session.commit()


def _payload(**overrides) -> dict:
    payload = {
        "email": f"{EMAIL_PREFIX}{uuid4().hex[:10]}@oncare.com",
        "password": PASSWORD,
        "name": "형식 검사 회원",
    }
    payload.update(overrides)
    return payload


@pytest.mark.parametrize("email", ["not-an-email", "member@oncare", ""])
def test_register_rejects_malformed_email(client, email, _cleanup):
    r = client.post("/v1/auth/register", json=_payload(email=email))
    assert r.status_code == 422, r.text


@pytest.mark.parametrize("phone", ["010-1234-567", "0101234", "전화번호"])
def test_register_rejects_malformed_phone(client, phone, _cleanup):
    r = client.post("/v1/auth/register", json=_payload(phone=phone))
    assert r.status_code == 422, r.text


def test_register_stores_phone_in_one_shape(client, _cleanup):
    """하이픈 없이 보내도 저장·조회는 `000-0000-0000` 이다."""
    payload = _payload(phone="01012345678")
    r = client.post("/v1/auth/register", json=payload)
    assert r.status_code == 201, r.text

    login = client.post(
        "/v1/auth/login",
        data={"username": payload["email"], "password": PASSWORD},
    )
    assert login.status_code == 200, login.text
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}

    profile = client.get("/v1/users/me/profile", headers=headers)
    assert profile.status_code == 200, profile.text
    assert profile.json()["phone"] == "010-1234-5678"


def test_register_without_phone_still_works(client, _cleanup):
    """전화번호는 선택이다 — 안 보내도 가입은 된다."""
    r = client.post("/v1/auth/register", json=_payload())
    assert r.status_code == 201, r.text


def test_trainer_register_rejects_malformed_email(client, _cleanup):
    """트레이너 가입도 같은 기준이다 — 초대 코드를 보기 전에 형식에서 막힌다."""
    r = client.post(
        "/v1/auth/trainer/register",
        json=_payload(email="trainer@oncare", invite_code="WHATEVER"),
    )
    assert r.status_code == 422, r.text
