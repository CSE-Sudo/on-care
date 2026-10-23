"""코드 메일의 HTML 본문(#3490) — DB 불필요.

가입·이메일 변경 인증 코드와 비밀번호 재설정 코드 메일은 일반 텍스트에 더해 꾸민
HTML 을 함께 싣는다. 텍스트 본문은 예전 그대로여야 하고, HTML 에는 같은 코드와
유효 시간이 크게 들어가야 한다.
"""
from __future__ import annotations

import re
import smtplib

import pytest

from app.core.config import Settings
from app.models.models import User
from app.services import mailer, password_reset, signup_email_code
from app.services.mail_templates import BRAND, BRAND_STRONG, code_mail_html
from app.services.mailer import OutgoingMail, SmtpMailer
from app.services.signup_email_code import EMAIL_CHANGE, MEMBER_SIGNUP, TRAINER_SIGNUP

_SMTP = dict(smtp_host="smtp.example.com", mail_from="On-Care <no-reply@example.com>")


def _html(**kw) -> str:
    base = dict(
        title="이메일 인증 코드",
        lead="안내 문장",
        code="123456",
        minutes=10,
        ignore="무시 안내",
    )
    base.update(kw)
    return code_mail_html(**base)


# ---- 틀 ----


def test_template_shows_code_minutes_and_texts():
    html = _html()
    assert "123456" in html
    assert "10분" in html
    for text in ("이메일 인증 코드", "안내 문장", "무시 안내", "On-Care"):
        assert text in html


def test_code_is_large_and_brand_colored():
    html = _html()
    m = re.search(r'<div style="([^"]*)">123456</div>', html)
    assert m, "코드는 따로 꾸민 칸에 들어간다"
    style = m.group(1)
    size = int(re.search(r"font-size:(\d+)px", style).group(1))
    assert size >= 32
    assert BRAND_STRONG in style
    assert "letter-spacing" in style
    assert BRAND in html


def test_long_reset_code_stays_on_one_line():
    html = _html(code="K7QX-M2PA")
    style = re.search(r'<div style="([^"]*)">K7QX-M2PA</div>', html).group(1)
    assert "white-space:nowrap" in style
    size = int(re.search(r"font-size:(\d+)px", style).group(1))
    spacing = int(re.search(r"letter-spacing:(\d+)px", style).group(1))
    # 375pt 폰에서 상자 안쪽 폭은 250 남짓이다 — 글자당 폭을 넉넉히 0.65em 으로 본다.
    assert 9 * (size * 0.65 + spacing) <= 250


def test_template_is_a_full_korean_document():
    html = _html()
    assert html.startswith("<!doctype html>")
    assert '<html lang="ko">' in html
    assert '<meta charset="utf-8">' in html


@pytest.mark.parametrize(
    "field", ["title", "lead", "code", "ignore", "support", "link_label"]
)
def test_every_text_is_escaped(field):
    html = _html(**{field: "<script>alert(1)</script>&"}, link="https://x.test/r")
    assert "<script>" not in html
    assert "&lt;script&gt;" in html


def test_link_is_attribute_escaped():
    html = _html(link='https://x.test/r?a=1&b="2"', link_label="열기")
    assert 'href="https://x.test/r?a=1&amp;b=&quot;2&quot;"' in html


def test_no_external_resources_or_scripts():
    html = _html(link="https://x.test/r", link_label="열기", support="help@x.test")
    lowered = html.lower()
    for tag in ("<img", "<script", "<link", "<style", "@import", "url("):
        assert tag not in lowered, tag
    # 꾸밈은 인라인 스타일과 표 배치로만 한다.
    assert 'role="presentation"' in html


def test_button_only_with_link():
    assert "<a " not in _html()
    html = _html(link="https://x.test/r", link_label="새 비밀번호 정하기")
    assert "<a " in html
    assert "새 비밀번호 정하기" in html


def test_support_line_only_when_given():
    assert "문의:" not in _html()
    assert "문의: help@x.test" in _html(support="help@x.test")


# ---- 인증 코드 메일 ----


def _signup(purpose: str = MEMBER_SIGNUP, **settings) -> OutgoingMail:
    return signup_email_code._compose_code(
        "member@example.com",
        "482913",
        10,
        Settings(_env_file=None, **settings),
        purpose,
    )


@pytest.mark.parametrize("purpose", [MEMBER_SIGNUP, TRAINER_SIGNUP, EMAIL_CHANGE])
def test_signup_code_mail_has_html_with_the_code(purpose):
    mail = _signup(purpose)
    assert mail.html
    assert "482913" in mail.html
    assert "10분" in mail.html


def test_signup_text_body_is_unchanged():
    mail = _signup()
    assert mail.body.splitlines()[:6] == [
        "On-Care 가입을 위해 이메일 인증 코드를 보내 드립니다.",
        "",
        "인증 코드: 482913",
        "이 코드는 10분 동안 한 번만 쓸 수 있습니다.",
        "",
        "직접 가입하지 않으셨다면 이 메일을 무시하세요. 계정이 만들어지지 않습니다.",
    ]
    assert mail.subject == "[On-Care] 이메일 인증 코드"


def test_email_change_html_says_change():
    html = _signup(EMAIL_CHANGE).html
    assert "이메일 변경 인증 코드" in html
    assert "로그인 이메일을 이 주소로 바꾸기" in html
    assert "어떤 계정의 이메일도 이 주소로" in html


def test_signup_html_has_no_link_button():
    assert "<a " not in _signup().html


def test_signup_html_carries_support_contact():
    mail = _signup(mail_support_contact="help@oncare.test")
    assert "문의: help@oncare.test" in mail.body
    assert "문의: help@oncare.test" in mail.html
    assert "문의:" not in _signup().html


def test_already_registered_notice_stays_text_only():
    mail = signup_email_code._compose_already_registered(
        "member@example.com", Settings(_env_file=None)
    )
    assert mail.html is None


# ---- 재설정 코드 메일 ----


def _reset(link: str = "") -> OutgoingMail:
    return password_reset._compose(
        User(email="member@example.com"), "K7QX-M2PA", 15, link
    )


def test_reset_mail_has_html_with_the_code():
    mail = _reset()
    assert "K7QX-M2PA" in mail.html
    assert "15분" in mail.html
    assert "비밀번호 재설정 코드" in mail.html
    assert "비밀번호는 바뀌지 않습니다" in mail.html


def test_reset_link_becomes_a_button():
    mail = _reset("https://oncarefit.com/member/reset?token=abc")
    assert 'href="https://oncarefit.com/member/reset?token=abc"' in mail.html
    assert "새 비밀번호 정하기" in mail.html
    assert "https://oncarefit.com/member/reset?token=abc" in mail.body


def test_reset_without_link_has_no_button():
    assert "<a " not in _reset().html


def test_reset_text_body_is_unchanged():
    assert _reset().body.splitlines() == [
        "On-Care 비밀번호 재설정을 요청하셨습니다.",
        "",
        "재설정 코드: K7QX-M2PA",
        "이 코드는 15분 동안 한 번만 쓸 수 있습니다.",
        "",
        "직접 요청하지 않으셨다면 이 메일을 무시하세요. 비밀번호는 바뀌지 않습니다.",
    ]


# ---- SMTP 메시지 ----


class _FakeSMTP:
    sent: list = []

    def __init__(self, *args, **kwargs):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def starttls(self, context=None):
        pass

    def login(self, user, password):
        pass

    def send_message(self, msg):
        _FakeSMTP.sent.append(msg)


@pytest.fixture
def sent(monkeypatch):
    _FakeSMTP.sent = []
    monkeypatch.setattr(mailer.smtplib, "SMTP", _FakeSMTP)
    monkeypatch.setattr(mailer.smtplib, "SMTP_SSL", _FakeSMTP)
    return _FakeSMTP.sent


def test_smtp_sends_text_and_html_alternatives(sent):
    SmtpMailer(Settings(_env_file=None, **_SMTP)).send(_signup())
    msg = sent[0]
    assert msg.get_content_type() == "multipart/alternative"
    parts = list(msg.iter_parts())
    assert [p.get_content_type() for p in parts] == ["text/plain", "text/html"]
    assert "인증 코드: 482913" in parts[0].get_content()
    assert "482913" in parts[1].get_content()
    # 메일 앱은 마지막 대안(HTML)을 먼저 고른다.
    assert msg.get_body(preferencelist=("html", "plain")) is parts[1]


def test_smtp_without_html_stays_plain_text(sent):
    SmtpMailer(Settings(_env_file=None, **_SMTP)).send(
        OutgoingMail(to="member@example.com", subject="제목", body="본문")
    )
    msg = sent[0]
    assert msg.get_content_type() == "text/plain"
    assert not msg.is_multipart()


def test_smtp_module_is_real_smtplib():
    # 가짜를 바꿔 끼우는 대상이 표준 모듈이어야 위 확인이 실제 발송 경로를 본다.
    assert mailer.smtplib is smtplib
