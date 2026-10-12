"""아이디(가입 이메일) 찾기의 순수 규칙(#3337) — 이메일 가리기와 요청 스키마. DB 없이 돈다."""
from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.schemas.user import FindEmailRequest
from app.services import find_email


@pytest.mark.parametrize(
    ("address", "masked"),
    [
        ("abcdef@example.com", "ab***@example.com"),
        ("abc@example.com", "ab***@example.com"),
        # 두 글자 이하는 덜 보여 준다 — 한 글자는 반드시 가린다.
        ("ab@example.com", "a***@example.com"),
        ("a@example.com", "***@example.com"),
        ("@example.com", "***@example.com"),
        ("not-an-email", "***"),
    ],
)
def test_mask_email(address: str, masked: str) -> None:
    assert find_email.mask_email(address) == masked


@pytest.mark.parametrize("local", ["a", "ab", "abc", "abcdefghijkl"])
def test_mask_never_shows_the_whole_local_part(local: str) -> None:
    masked = find_email.mask_email(f"{local}@example.com")
    shown = masked.split(find_email.MASK)[0]
    assert len(shown) < len(local)
    assert f"{local}@" not in masked


def test_mask_length_does_not_follow_address_length() -> None:
    """가린 자리는 늘 같은 길이다 — 주소 길이가 드러나지 않는다."""
    short = find_email.mask_email("abc@example.com")
    long = find_email.mask_email("abcdefghijklmnop@example.com")
    assert short == long


def test_placeholder_email_is_recognised() -> None:
    assert find_email._is_placeholder_email("kakao_12345@social.oncare")
    assert find_email._is_placeholder_email("KAKAO_12345@SOCIAL.ONCARE")
    assert not find_email._is_placeholder_email("member@oncare.com")


def test_request_normalizes_phone_and_name() -> None:
    req = FindEmailRequest(name="  김온케어 ", phone="01012345678")
    assert req.name == "김온케어"
    assert req.phone == "010-1234-5678"


@pytest.mark.parametrize("phone", ["", "   ", "0101234", "011-1234-5678", "abc"])
def test_request_rejects_blank_or_malformed_phone(phone: str) -> None:
    """빈 번호를 받으면 번호를 넣지 않은 계정이 이름만으로 걸린다."""
    with pytest.raises(ValidationError):
        FindEmailRequest(name="김온케어", phone=phone)


@pytest.mark.parametrize("name", ["", "   "])
def test_request_rejects_blank_name(name: str) -> None:
    with pytest.raises(ValidationError):
        FindEmailRequest(name=name, phone="010-1234-5678")
