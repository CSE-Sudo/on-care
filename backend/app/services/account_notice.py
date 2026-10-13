"""계정 보안 안내 메일(#3038·#3039).

본인이 한 일인지 알아챌 수 있도록 계정의 중요한 변화를 **이전 주소**로 알린다.
지금은 로그인 이메일 변경 하나다 — 남이 바꿨다면 새 주소로는 알릴 수 없으므로 옛
주소로 보낸다. 발송 실패는 저장을 되돌리지 않는다(로그만 남긴다).

메일 끝의 문의처는 `MAIL_SUPPORT_CONTACT` 한 곳에서 읽는다 — 가입 인증 메일도 같다.
"""
from __future__ import annotations

import logging

from app.core.config import Settings, get_settings
from app.services.mailer import (
    Mailer,
    MailDeliveryError,
    OutgoingMail,
    get_mailer,
    mask_email,
)
from app.services.placeholder_email import is_placeholder_email

log = logging.getLogger(__name__)


def support_lines(settings: Settings) -> list[str]:
    """메일 끝 문의처 줄. 설정이 비면 넣지 않는다."""
    contact = settings.mail_support_contact.strip()
    if not contact:
        return []
    return ["", f"문의: {contact}"]


def compose_email_changed(
    old_email: str, new_email: str, *, settings: Settings
) -> OutgoingMail:
    """옛 주소로 보내는 이메일 변경 안내. 새 주소는 가려서 적는다."""
    subject = "[On-Care] 로그인 이메일이 바뀌었습니다"
    lines = [
        "On-Care 계정의 로그인 이메일이 바뀌었습니다.",
        f"새 이메일: {mask_email(new_email)}",
        "다른 기기에서는 모두 로그아웃되었습니다.",
        "",
        "직접 바꾸지 않으셨다면 바로 문의해 주세요.",
    ]
    lines += support_lines(settings)
    return OutgoingMail(to=old_email, subject=subject, body="\n".join(lines))


def send_email_changed(
    old_email: str,
    new_email: str,
    *,
    settings: Settings | None = None,
    mailer: Mailer | None = None,
) -> bool:
    """이메일 변경 안내를 옛 주소로 보낸다. 실제로 보냈으면 True.

    서버에 발송 수단이 없으면(운영인데 SMTP 가 비었을 때) 보내지 않는다 — 변경 자체는
    막지 않는다. 실패는 로그로만 남긴다.

    옛 주소가 소셜 가입의 대체 이메일이면 보내지 않는다(#3338) — 받는 사람이 없는
    내부용 주소다. 처음으로 실제 주소를 넣는 저장이라 알릴 이전 주소가 없다.
    """
    if is_placeholder_email(old_email):
        return False
    settings = settings or get_settings()
    if not settings.mail_enabled:
        log.warning("메일 발송 수단이 없어 이메일 변경 안내를 보내지 않음: %s", mask_email(old_email))
        return False
    mail = compose_email_changed(old_email, new_email, settings=settings)
    try:
        (mailer or get_mailer(settings)).send(mail)
    except MailDeliveryError as exc:
        log.error("이메일 변경 안내 발송 실패: to=%s err=%s", mask_email(old_email), exc)
        return False
    return True
