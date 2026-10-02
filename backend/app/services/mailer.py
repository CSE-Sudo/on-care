"""메일 발송 계층(#2824).

비밀번호 재설정이 처음으로 메일을 보내는 기능이다. 발송 수단은 설정으로 고르고,
호출하는 쪽은 [Mailer] 하나만 본다.

* **log** — 실제로 보내지 않고 서버 로그에 남긴다. 개발·스테이징에서 쓰고, 개발자는
  로그에서 재설정 코드를 읽어 흐름을 확인한다. 운영에서는 쓰지 않는다
  (`Settings.mail_enabled` 가 막는다).
* **smtp** — 표준 SMTP. AWS SES 도 SMTP 엔드포인트를 주므로 같은 구현으로 쓴다.
  서버·계정·발신 주소는 환경변수로만 받는다.

발송 실패는 [MailDeliveryError] 로 던진다. 재설정 요청은 이 실패를 응답에 싣지 않고
로그만 남긴다 — 실패 여부가 응답에 드러나면 계정 존재 여부가 함께 드러난다.
"""
from __future__ import annotations

import logging
import smtplib
import ssl
from dataclasses import dataclass
from email.message import EmailMessage
from email.utils import formataddr, parseaddr
from typing import Protocol

from app.core.config import Settings, get_settings

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class OutgoingMail:
    """보낼 메일 한 통. 본문은 일반 텍스트다 — 링크 하나와 코드 하나면 충분하다."""

    to: str
    subject: str
    body: str


class MailDeliveryError(Exception):
    """메일을 넘기지 못했다(연결·인증·거부). 원인은 `__cause__` 에 있다."""


class Mailer(Protocol):
    """메일 발송 수단."""

    #: 로그·진단에 쓰는 이름(`log`|`smtp`).
    name: str

    def send(self, mail: OutgoingMail) -> None: ...


def mask_email(address: str) -> str:
    """로그용 이메일 가림. `ab***@example.com` 모양으로 앞 두 글자와 도메인만 남긴다."""
    local, _, domain = address.partition("@")
    if not domain:
        return "***"
    return f"{local[:2]}***@{domain}"


class LogMailer:
    """보내지 않고 로그에 남긴다(개발용).

    본문(재설정 코드 포함)은 DEBUG 로만 남긴다. 받는 사람은 가려 적는다 — 개발
    로그라도 다른 사람 주소가 그대로 쌓일 이유는 없다.
    """

    name = "log"

    def send(self, mail: OutgoingMail) -> None:
        log.warning(
            "메일 발송 수단이 설정되지 않아 보내지 않고 로그에만 남깁니다: to=%s subject=%s",
            mask_email(mail.to),
            mail.subject,
        )
        log.debug("메일 본문(개발용):\n%s", mail.body)


class SmtpMailer:
    """SMTP 로 보낸다. AWS SES SMTP 엔드포인트도 이 구현을 쓴다."""

    name = "smtp"

    def __init__(self, settings: Settings) -> None:
        self._host = settings.smtp_host.strip()
        self._port = settings.smtp_port
        self._username = settings.smtp_username
        self._password = settings.smtp_password
        self._starttls = settings.smtp_starttls
        self._ssl = settings.smtp_ssl
        self._timeout = settings.smtp_timeout_seconds
        self._sender = settings.mail_from.strip()

    def _message(self, mail: OutgoingMail) -> EmailMessage:
        msg = EmailMessage()
        name, address = parseaddr(self._sender)
        msg["From"] = formataddr((name, address)) if name else address
        msg["To"] = mail.to
        msg["Subject"] = mail.subject
        msg.set_content(mail.body)
        return msg

    def send(self, mail: OutgoingMail) -> None:
        msg = self._message(mail)
        context = ssl.create_default_context()
        try:
            if self._ssl:
                server: smtplib.SMTP = smtplib.SMTP_SSL(
                    self._host, self._port, timeout=self._timeout, context=context
                )
            else:
                server = smtplib.SMTP(self._host, self._port, timeout=self._timeout)
            with server:
                if not self._ssl and self._starttls:
                    server.starttls(context=context)
                if self._username:
                    server.login(self._username, self._password)
                server.send_message(msg)
        except (smtplib.SMTPException, OSError) as exc:
            raise MailDeliveryError(str(exc)) from exc


def get_mailer(settings: Settings | None = None) -> Mailer:
    """설정이 고른 발송 수단. 테스트는 이 함수를 바꿔 끼워 보낸 메일을 모은다."""
    settings = settings or get_settings()
    if settings.mail_backend == "smtp":
        return SmtpMailer(settings)
    return LogMailer()


def warn_if_disabled(settings: Settings | None = None) -> bool:
    """기동 때 부른다 — 메일을 보낼 수 없으면 오류 로그로 드러내고 False.

    운영에서 발송 수단 없이 뜨면 비밀번호 재설정이 꺼진다. 기동을 막지는 않는다:
    로그인·기록 같은 나머지 기능까지 멈출 일은 아니고, 재설정 요청은 503 으로
    분명히 거절된다.
    """
    settings = settings or get_settings()
    if settings.mail_enabled:
        if settings.mail_backend == "log":
            log.warning(
                "메일 발송 수단이 없어 재설정 메일을 로그로만 남깁니다(env=%s). "
                "운영에서는 SMTP_HOST·MAIL_FROM 을 설정하세요.",
                settings.env,
            )
        return True
    log.error(
        "운영(env=%s)인데 메일 발송 설정(SMTP_HOST·MAIL_FROM)이 없어 비밀번호 재설정이 "
        "꺼져 있습니다. /auth/password-reset/request 는 503 으로 응답합니다.",
        settings.env,
    )
    return False
