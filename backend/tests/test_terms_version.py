"""약관 버전과 두 앱 이용약관 부칙의 시행일이 맞물리는지. (#3006)

가입 동의는 `signup_consent.CURRENT_VERSIONS["terms"]` 로 "어느 약관에 동의했는지" 를
남긴다. 약관에 포인트·쿠폰·예약·해지 효과 조항을 더하면서 버전을 올렸다. 본문 시행일과
버전이 갈리면 동의 기록이 화면에 없는 문서를 가리키게 된다.

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

_KO_EFFECTIVE = re.compile(r"(\d{4})년 (\d{1,2})월 (\d{1,2})일부터 시행")
_KO_ARTICLE = re.compile(r"^제(\d+)조 ", re.MULTILINE)


def _arb(app: str, lang: str) -> dict[str, str]:
    path = _ROOT / "frontend" / app / "lib" / "l10n" / f"app_{lang}.arb"
    return json.loads(path.read_text(encoding="utf-8"))


def _terms_body(app: str, lang: str) -> str:
    return _arb(app, lang)["myLegalTermsBody"]


def _terms_version() -> date:
    return date.fromisoformat(signup_consent.CURRENT_VERSIONS[signup_consent.TERMS])


@pytest.mark.parametrize("app", _APPS)
def test_korean_effective_date_is_the_consent_version(app: str):
    """한국어 원본 부칙의 시행일이 동의 기록 버전과 같은 날이다."""
    found = _KO_EFFECTIVE.findall(_terms_body(app, "ko"))
    assert len(found) == 1, "시행일 문장이 하나여야 한다"
    y, m, d = (int(x) for x in found[0])
    assert date(y, m, d) == _terms_version()


@pytest.mark.parametrize("app", _APPS)
def test_english_effective_date_is_the_consent_version(app: str):
    """영문본도 같은 날짜를 단다."""
    v = _terms_version()
    body = _terms_body(app, "en")
    month = v.strftime("%B")
    assert f"{v.day} {month} {v.year}" in body or f"{month} {v.day}, {v.year}" in body


@pytest.mark.parametrize("app", _APPS)
def test_revision_history_keeps_first_issue(app: str):
    """개정 이력에 제정일이 남는다 — 이전 버전에 동의한 계정이 어느 문서였는지 안다."""
    assert "2026년 10월 1일: 제정" in _terms_body(app, "ko")


@pytest.mark.parametrize("app", _APPS)
def test_articles_are_numbered_in_order(app: str):
    """조 번호가 1부터 빠짐없이 이어진다 — 조를 끼워 넣다 번호가 꼬이지 않았는지."""
    numbers = [int(n) for n in _KO_ARTICLE.findall(_terms_body(app, "ko"))]
    assert numbers == list(range(1, len(numbers) + 1))


def test_member_terms_cover_points_coupons_and_termination():
    """회원 약관에 포인트·쿠폰·해지 효과·분쟁 해결 조항이 있다(#3006)."""
    body = _terms_body("flutter", "ko")
    for title in ("(포인트)", "(쿠폰과 교환 상품)", "(이용 계약의 해지와 그 효과)", "(분쟁 해결과 관할)"):
        assert title in body, title


def test_trainer_terms_cover_coupon_redemption_and_disputes():
    """트레이너 약관에 쿠폰 사용 처리·이용 제한·분쟁 해결 조항이 있다(#3006)."""
    body = _terms_body("flutter_trainer", "ko")
    for title in ("(회원 쿠폰의 사용 처리)", "(이용 제한)", "(분쟁 해결과 관할)"):
        assert title in body, title


def test_terms_version_is_newer_than_first_issue():
    """약관 본문을 고쳤으니 버전이 제정일보다 뒤다 — 기존 계정이 다시 동의한다."""
    assert _terms_version() > date(2026, 10, 1)
