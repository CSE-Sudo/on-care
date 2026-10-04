"""비밀번호 재설정 코드 규칙(#2824) — DB 불필요.

코드는 사람이 메일에서 옮겨 칠 수도 있는 값이라, 모양·정규화·해시가 서로 어긋나면
"메일에 적힌 대로 쳤는데 안 된다" 가 된다.
"""
from __future__ import annotations

import re

import pytest

from app.services import password_reset as pr


def test_code_shape():
    code = pr.generate_code()
    assert re.fullmatch(r"[A-Z2-9]{4}(-[A-Z2-9]{4}){3}", code), code
    assert len(pr.normalize_code(code)) == pr.CODE_LENGTH


def test_code_avoids_confusable_letters():
    """0/O, 1/I/L 은 옮겨 적다 틀리기 쉬워 쓰지 않는다."""
    for ch in "01OIL":
        assert ch not in pr.CODE_ALPHABET
    seen = "".join(pr.generate_code() for _ in range(200))
    assert not set(seen) & set("01OIL")


def test_codes_are_unique_enough():
    assert len({pr.generate_code() for _ in range(500)}) == 500


@pytest.mark.parametrize(
    "typed",
    [
        "ABCD-EFGH-JKMN-PQRS",
        "abcd-efgh-jkmn-pqrs",
        "ABCDEFGHJKMNPQRS",
        " ABCD EFGH JKMN PQRS ",
        "abcd efgh-JKMN pqrs\n",
    ],
)
def test_normalize_ignores_case_spaces_and_hyphens(typed):
    assert pr.normalize_code(typed) == "ABCDEFGHJKMNPQRS"


def test_hash_matches_across_typings():
    """메일의 모양 그대로든, 소문자로 붙여 쳤든 같은 행을 찾아야 한다."""
    assert pr.hash_code("ABCD-EFGH-JKMN-PQRS") == pr.hash_code("abcdefghjkmnpqrs")
    assert pr.hash_code("ABCD-EFGH-JKMN-PQRS") != pr.hash_code("ABCD-EFGH-JKMN-PQRT")
    assert re.fullmatch(r"[0-9a-f]{64}", pr.hash_code("ABCD-EFGH-JKMN-PQRS"))


def test_hash_is_not_the_code():
    code = pr.generate_code()
    assert pr.normalize_code(code) not in pr.hash_code(code)


@pytest.mark.parametrize(
    ("base", "expected"),
    [
        ("", ""),
        ("   ", ""),
        (
            "https://app.example.com/auth/password-reset",
            "https://app.example.com/auth/password-reset?token=ABCD-EFGH-JKMN-PQRS",
        ),
        (
            "https://app.example.com/reset?lang=ko",
            "https://app.example.com/reset?lang=ko&token=ABCD-EFGH-JKMN-PQRS",
        ),
        # 두 앱의 실제 배포 형식 — 해시 URL 전략·하위 경로(#3033).
        (
            "https://oncare.example/frontend/#/auth/password-reset",
            "https://oncare.example/frontend/#/auth/password-reset?token=ABCD-EFGH-JKMN-PQRS",
        ),
        (
            "https://oncare.example/trainer/#/auth/password-reset",
            "https://oncare.example/trainer/#/auth/password-reset?token=ABCD-EFGH-JKMN-PQRS",
        ),
        # 해시 안에 이미 쿼리가 있으면 이어 붙인다.
        (
            "https://oncare.example/trainer/#/auth/password-reset?lang=ko",
            "https://oncare.example/trainer/#/auth/password-reset?lang=ko&token=ABCD-EFGH-JKMN-PQRS",
        ),
        # 해시 앞의 쿼리는 앱이 읽지 않는다 — 토큰은 해시 안으로 간다.
        (
            "https://oncare.example/trainer/?ref=mail#/auth/password-reset",
            "https://oncare.example/trainer/?ref=mail#/auth/password-reset?token=ABCD-EFGH-JKMN-PQRS",
        ),
        # 끝이 이미 구분자면 두 번 붙이지 않는다.
        (
            "https://oncare.example/frontend/#/auth/password-reset?",
            "https://oncare.example/frontend/#/auth/password-reset?token=ABCD-EFGH-JKMN-PQRS",
        ),
        ("  https://oncare.example/frontend/#/auth/password-reset  ",
         "https://oncare.example/frontend/#/auth/password-reset?token=ABCD-EFGH-JKMN-PQRS"),
    ],
)
def test_reset_link(base, expected):
    assert pr.reset_link(base, "ABCD-EFGH-JKMN-PQRS") == expected


def test_reset_link_encodes_the_token():
    """토큰은 URL 인코딩된다 — 앱이 쿼리로 읽을 때 그대로 돌아온다."""
    link = pr.reset_link("https://oncare.example/frontend/#/auth/password-reset", "A B&C")
    assert link.endswith("?token=A+B%26C")


@pytest.mark.parametrize(
    ("url", "problem"),
    [
        ("", None),
        ("   ", None),
        ("https://oncare.example/frontend/#/auth/password-reset", None),
        ("https://oncare.example/trainer/?ref=mail#/auth/password-reset", None),
        ("https://oncare.example/auth/password-reset", "해시"),
        ("https://oncare.example/frontend/#auth/password-reset", "해시"),
        ("http://oncare.example/frontend/#/auth/password-reset", "https"),
        ("oncare.example/frontend/#/auth/password-reset", "https"),
    ],
)
def test_reset_url_problem(url, problem):
    found = pr.reset_url_problem(url)
    if problem is None:
        assert found is None
    else:
        assert found is not None and problem in found
