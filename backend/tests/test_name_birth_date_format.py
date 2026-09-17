"""이름·생년월일의 서버 형식 검증. (#1887)

앞부분(`clean_name`/`clean_birth_date`/`name_from_email`)은 DB 없이 도는 순수
검사다. 뒤의 가입 엔드포인트 검사는 `client` 픽스처를 쓰므로 로컬에서는 skip
되고 CI 에서 돈다. 프로필 수정·온보딩 경로는 `test_profile.py` 에 있다.

여기서 확인하는 것은 두 가지다. **컬럼 길이를 넘는 값이 500 이 아니라 422 로
막히는가**, 그리고 **날짜가 아닌 생년월일이 저장되지 않는가**. 둘 다 전에는
그대로 컬럼에 닿았다.
"""
from __future__ import annotations

from uuid import uuid4

import pytest

from app.models.models import HealthProfile, User
from app.services.profile_format import (
    NAME_MAX_LENGTH,
    InvalidBirthDate,
    InvalidName,
    clean_birth_date,
    clean_name,
    name_from_email,
)

EMAIL_PREFIX = "name-format-"
PASSWORD = "name-pw-1234"


# ---- 형식 규칙 (DB 불필요) ----


@pytest.mark.parametrize(
    "value,cleaned",
    [
        ("김회원", "김회원"),
        ("  김회원  ", "김회원"),  # 앞뒤 공백은 잘라낸다
        ("가" * NAME_MAX_LENGTH, "가" * NAME_MAX_LENGTH),  # 상한 바로 안
    ],
)
def test_clean_name_accepts_ordinary_names(value, cleaned):
    assert clean_name(value) == cleaned


@pytest.mark.parametrize("value", ["", "   ", "가" * (NAME_MAX_LENGTH + 1)])
def test_clean_name_rejects_blank_and_too_long(value):
    with pytest.raises(InvalidName):
        clean_name(value)


def test_name_from_email_fits_the_column():
    """긴 주소로 가입해도 이름은 컬럼에 들어간다.

    이메일은 255자까지 받는데(#1780) `users.name` 은 100자다. 자르지 않으면
    **이름을 안 보냈을 뿐인데** 가입이 `value too long` 500 으로 떨어졌다.
    """
    long_local = "a" * 120
    assert name_from_email(f"{long_local}@oncare.com") == "a" * NAME_MAX_LENGTH
    assert name_from_email("member@oncare.com") == "member"


@pytest.mark.parametrize("value", ["1990-01-01", "  1990-01-01  ", "2026-02-28"])
def test_clean_birth_date_accepts_ymd(value):
    assert clean_birth_date(value) == value.strip()


def test_clean_birth_date_keeps_empty_empty():
    """비울 수 있는 값이다 — 넣을 자리가 없던 시절에 가입한 회원에게는 없다."""
    assert clean_birth_date("") == ""
    assert clean_birth_date("   ") == ""


@pytest.mark.parametrize(
    "value",
    [
        "asdfghjkl",  # 날짜가 아니다
        "1990-01-01T00:00:00Z",  # 컬럼 길이(10)를 넘겨 전에는 500 이었다
        "19900101",  # date.fromisoformat 은 받지만 컬럼 표기가 아니다
        "1990-13-45",  # 표기는 맞지만 실제 날짜가 아니다
        "90-01-01",
    ],
)
def test_clean_birth_date_rejects_non_dates(value):
    with pytest.raises(InvalidBirthDate):
        clean_birth_date(value)


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


def test_register_without_name_uses_a_name_that_fits(client, _cleanup):
    """이름을 생략한 가입이 긴 이메일 때문에 실패하지 않는다.

    이 가입이 500 이던 것이 #1887 에서 가장 나쁜 자리였다 — 사용자가 무엇을
    잘못했는지 알 방법이 없다.
    """
    local = f"{EMAIL_PREFIX}{'a' * 110}"
    payload = _payload(email=f"{local}@oncare.com")
    del payload["name"]  # 이름을 보내지 않은 가입이다
    r = client.post("/v1/auth/register", json=payload)
    assert r.status_code == 201, r.text
    assert r.json()["name"] == local[:NAME_MAX_LENGTH]


def test_register_rejects_a_name_longer_than_the_column(client, _cleanup):
    """상한 바로 바깥은 422 — 전에는 500 이었다."""
    r = client.post("/v1/auth/register", json=_payload(name="가" * (NAME_MAX_LENGTH + 1)))
    assert r.status_code == 422, r.text


def test_register_accepts_a_name_at_the_limit(client, _cleanup):
    """상한 바로 안은 지금도 받는다."""
    name = "가" * NAME_MAX_LENGTH
    r = client.post("/v1/auth/register", json=_payload(name=name))
    assert r.status_code == 201, r.text
    assert r.json()["name"] == name
