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
    _ROOT / "frontend" / app / "lib" / "l10n" / "app_ko.arb" for app in _APPS
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
    """본문의 시행일이 동의 기록 버전과 같은 날이다."""
    found = _KO_EFFECTIVE.findall(_privacy_body(app, "ko"))
    assert len(found) == 1, "시행일 줄이 하나여야 한다"
    y, m, d = (int(x) for x in found[0])
    assert date(y, m, d) == _privacy_version()


def test_effective_date_is_not_the_old_placeholder():
    """서비스와 무관한 자리표시자(2026-01-01)로 돌아가지 않는다."""
    assert _privacy_version() != date(2026, 1, 1)
    for app in _APPS:
        assert "2026년 1월 1일" not in _privacy_body(app, "ko")


_KO_REVISION = re.compile(r"^- (\d{4})년 (\d{1,2})월 (\d{1,2})일: ", re.MULTILINE)


@pytest.mark.parametrize("app", _APPS)
def test_newest_revision_entry_is_the_consent_version(app: str):
    """개정 이력의 맨 위 항목이 지금 동의받는 버전이다 — 이력 없이 버전만 오르지 않는다."""
    entries = _KO_REVISION.findall(_privacy_body(app, "ko"))
    assert entries, "개정 이력 항목이 없다"
    newest = max(date(int(y), int(m), int(d)) for y, m, d in entries)
    first = date(*(int(x) for x in entries[0]))
    assert first == newest, "개정 이력은 최신순이어야 한다"
    assert newest == _privacy_version()


@pytest.mark.parametrize("app", _APPS)
def test_contact_change_is_recorded_in_the_history(app: str):
    """보호책임자 연락처 변경(#3132)이 개정 이력에 남는다."""
    assert "개인정보 보호책임자 연락처 변경" in _privacy_body(app, "ko")


def test_naver_apple_removal_is_folded_into_the_unreleased_revision():
    """네이버·애플 로그인 제외(#3217)는 미배포 2026-10-05 판에 합쳤다 — 버전을 새로 만들지 않는다.

    같은 날짜 안에서 두 번째 버전을 만들 수 없고(버전이 날짜 문자열), 그 판은 아직
    배포 전이라 재동의를 다시 요구할 실익이 없다. 그래서 동의 버전은 그대로이고,
    회원 앱 처리방침의 같은 날짜 개정 이력에 제외 사실을 덧붙였다. 그 뒤 메일 발송 위탁
    추가(#3443)로 버전이 2026-10-14 로 올랐지만, 제외 사실은 2026-10-05 줄에 그대로 있다.
    """
    assert _privacy_version() >= date(2026, 10, 5)
    ko = _privacy_body("flutter", "ko")
    # 같은 날짜 개정(위치정보 동의 안내, #3136)과 한 줄로 합쳐져 있다.
    assert "- 2026년 10월 5일: 개인정보 보호책임자 연락처 변경," in ko
    assert "소셜 로그인 수단에서 네이버·애플 제외" in ko
    # 수집 항목에는 실제로 제공하는 소셜 로그인만 남는다.
    assert "소셜 로그인(카카오·구글)" in ko


@pytest.mark.parametrize("app", _APPS)
def test_naver_apple_appear_only_in_the_revision_history(app: str):
    """네이버·애플은 제외를 알리는 개정 이력 줄 말고는 처리방침에 나오지 않는다(#3217)."""
    lines = [
        line
        for line in _privacy_body(app, "ko").splitlines()
        if any(word in line for word in ("네이버", "애플"))
    ]
    for line in lines:
        assert line.startswith("- 2026년 10월 5일: "), line


def test_contact_placeholder_is_kept_in_every_body():
    """연락처는 본문에 박지 않고 `{contact}` 자리로 둔다 — 정의 지점은 한 곳이다(#3005)."""
    for app in _APPS:
        body = _privacy_body(app, "ko")
        assert "{contact}" in body
        assert "@" not in body.replace("{contact}", "")


_MAIL_RETENTION = "발신 계정의 보낸편지함에서 삭제하거나 위탁 계약이 끝날 때까지"


@pytest.mark.parametrize("app", _APPS)
def test_mail_processor_is_disclosed_as_trust_and_overseas_transfer(app: str):
    """운영 메일(Gmail SMTP, #480)의 위탁(6항)과 국외 이전(7항)을 함께 알린다(#3443).

    `docs/privacy_processing.md` 1절 Google LLC(Gmail) 행과 같은 사실이다. 이전 항목은
    받는 사람 주소와 메일 내용뿐이다 — 이름은 메일에 넣지 않는다(아래 테스트).
    """
    body = _privacy_body(app, "ko")
    trust, _, rest = body.partition("\n7. 개인정보의 국외 이전\n")
    transfer = rest.split("\n8. ", 1)[0]
    assert "- Google LLC: 가입 인증 코드, 비밀번호 재설정" in trust
    assert "메일 발송(Gmail)" in trust
    mail_lines = [
        line for line in transfer.splitlines() if line.startswith("⑤ Google LLC(Gmail) / ")
    ]
    assert len(mail_lines) == 1
    country, items, purpose, period = mail_lines[0].split(" / ")[1:]
    assert country == "미국 등 Google이 운영하는 데이터센터 소재 국가"
    assert items.startswith(
        "받는 사람의 이메일 주소와 메일 내용(인증 코드, 비밀번호 재설정 코드와 재설정 링크"
    )
    assert "메일 발송" in purpose
    assert period == _MAIL_RETENTION
    assert "그 메일을 보내기 위해 ⑤로 전송됩니다" in transfer
    assert (
        "- 2026년 10월 14일: 메일 발송 업체(Google LLC, Gmail)의 처리 위탁과 국외 이전 추가"
        in body
    )


def test_outgoing_mail_carries_only_the_disclosed_items():
    """처리방침이 적은 이전 항목(주소·코드·링크·가린 새 주소) 밖의 개인정보를 메일에 싣지 않는다."""
    from types import SimpleNamespace

    from app.services import account_notice, password_reset, signup_email_code

    settings = SimpleNamespace(mail_support_contact="")
    user = SimpleNamespace(email="member@example.com", name="홍길동", phone="01012345678")
    mails = [
        password_reset._compose(user, "123456", 30, "https://example.test/#/r?token=123456"),
        signup_email_code._compose_code("member@example.com", "123456", 10, settings),
        signup_email_code._compose_code(
            "new@example.com", "123456", 10, settings, purpose=signup_email_code.EMAIL_CHANGE
        ),
        signup_email_code._compose_already_registered("member@example.com", settings),
        account_notice.compose_email_changed(
            "member@example.com", "new@example.com", settings=settings
        ),
    ]
    for mail in mails:
        assert "홍길동" not in mail.body
        assert "01012345678" not in mail.body
    # 이메일 변경 안내는 새 주소를 가려 적는다.
    assert "new@example.com" not in mails[-1].body
