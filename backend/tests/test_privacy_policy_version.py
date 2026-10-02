"""처리방침 버전과 두 앱 처리방침 본문의 시행일이 맞물리는지. (#2820)

가입 동의는 `signup_consent.CURRENT_VERSIONS["privacy"]` 로 "어느 버전에 동의했는지" 를
남긴다. 그런데 회원이 실제로 읽는 본문은 두 앱의 ARB 에 있다. 본문만 고치고 버전을 그대로
두면 바뀐 내용에 아무도 다시 동의하지 않고, 버전만 올리고 본문 시행일을 두면 동의 기록이
가리키는 문서가 화면에 없는 날짜를 단다.

DB 없이 돈다. 프론트 소스가 없는 체크아웃에서는 건너뛴다.
"""
from __future__ import annotations

import json
import re
from datetime import date
from pathlib import Path

import pytest

from app.services import signup_consent

_ROOT = Path(__file__).resolve().parents[2]
_APPS = ("flutter", "flutter_trainer")
_ARBS = [
    _ROOT / "frontend" / app / "lib" / "l10n" / f"app_{lang}.arb"
    for app in _APPS
    for lang in ("ko", "en")
]

pytestmark = pytest.mark.skipif(
    not all(p.exists() for p in _ARBS), reason="프론트 소스가 없는 체크아웃"
)

_KO_EFFECTIVE = re.compile(r"시행일: (\d{4})년 (\d{1,2})월 (\d{1,2})일")


def _privacy_body(app: str, lang: str) -> str:
    path = _ROOT / "frontend" / app / "lib" / "l10n" / f"app_{lang}.arb"
    return json.loads(path.read_text(encoding="utf-8"))["myLegalPrivacyBody"]


def _privacy_version() -> date:
    return date.fromisoformat(signup_consent.CURRENT_VERSIONS[signup_consent.PRIVACY])


@pytest.mark.parametrize("app", _APPS)
def test_korean_effective_date_is_the_consent_version(app: str):
    """한국어 원본의 시행일이 동의 기록 버전과 같은 날이다."""
    found = _KO_EFFECTIVE.findall(_privacy_body(app, "ko"))
    assert len(found) == 1, "시행일 줄이 하나여야 한다"
    y, m, d = (int(x) for x in found[0])
    assert date(y, m, d) == _privacy_version()


@pytest.mark.parametrize("app", _APPS)
def test_english_effective_date_is_the_consent_version(app: str):
    """영문본도 같은 날짜를 단다 — 두 언어의 시행일이 갈리면 안 된다."""
    v = _privacy_version()
    body = _privacy_body(app, "en")
    month = v.strftime("%B")
    assert f"{v.day} {month} {v.year}" in body or f"{month} {v.day}, {v.year}" in body


def test_effective_date_is_not_the_old_placeholder():
    """서비스와 무관한 자리표시자(2026-01-01)로 돌아가지 않는다."""
    assert _privacy_version() != date(2026, 1, 1)
    for app in _APPS:
        assert "2026년 1월 1일" not in _privacy_body(app, "ko")
