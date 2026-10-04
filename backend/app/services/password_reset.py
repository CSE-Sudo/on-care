"""비밀번호 재설정(#2824) — 로그아웃 상태에서 메일로 계정을 되찾는 길.

흐름은 두 단계다.

1. **요청** — 이메일을 받으면 그 계정 앞으로 일회용 코드를 만들어 메일로 보낸다.
   계정이 없거나, 쉬고 있거나, 소셜 로그인 전용(비밀번호 없음)이면 아무것도 보내지
   않는다. 어느 쪽이든 호출부는 **같은 응답**을 준다 — 응답이 다르면 아무 이메일이나
   넣어 가입 여부를 알아낼 수 있다.
2. **확인** — 코드와 새 비밀번호를 받으면 비밀번호를 바꾸고 토큰 세대를 올린다
   (#2766). 그 전에 나간 접근·refresh 토큰은 모든 기기에서 끊긴다. 확인은 새 토큰을
   주지 않는다 — 회원은 새 비밀번호로 다시 로그인한다.

코드는 사람이 옮겨 칠 수 있도록 헷갈리는 글자(0/O, 1/I/L)를 뺀 32글자에서 16자를
뽑아 `XXXX-XXXX-XXXX-XXXX` 로 보여 준다(80비트). 표에는 해시만 남긴다. 메일 링크를
열 수 없는 모바일 앱에서는 이 코드를 붙여 넣는다.
"""
from __future__ import annotations

import hashlib
import logging
import secrets
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from urllib.parse import urlencode, urlsplit

from sqlalchemy import delete, func, select, update
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.locale import Locale, localized
from app.core.security import hash_password
from app.models.models import PasswordResetToken, User
from app.services import auth_tokens
from app.services.contact_format import normalize_email
from app.services.mailer import (
    Mailer,
    MailDeliveryError,
    OutgoingMail,
    get_mailer,
    mask_email,
)

log = logging.getLogger(__name__)

#: 코드에 쓰는 글자. 0/O, 1/I/L 처럼 옮겨 적다 틀리기 쉬운 글자를 뺐다.
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
#: 코드 길이(구분자 제외).
CODE_LENGTH = 16
#: 보여 줄 때 몇 글자마다 `-` 를 넣는가.
CODE_GROUP = 4


class ResetUnavailable(Exception):
    """이 서버는 재설정 메일을 보낼 수 없다(운영인데 발송 설정이 없음)."""


class InvalidResetCode(Exception):
    """코드가 없거나, 만료됐거나, 이미 쓰였다. 어느 쪽인지는 밝히지 않는다."""


@dataclass(frozen=True)
class IssuedReset:
    """요청이 실제로 만든 코드. 계정이 없으면 만들지 않으므로 호출부에는 보이지
    않는다 — 테스트와 로그를 위한 값이다."""

    user_id: str
    code: str
    expires_at: datetime


def generate_code() -> str:
    """새 코드를 `XXXX-XXXX-XXXX-XXXX` 모양으로 만든다."""
    raw = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
    return "-".join(
        raw[i : i + CODE_GROUP] for i in range(0, CODE_LENGTH, CODE_GROUP)
    )


def normalize_code(value: str) -> str:
    """사람이 친 코드를 비교할 모양으로. 대소문자·공백·하이픈은 보지 않는다."""
    return "".join(ch for ch in value.upper() if ch.isalnum())


def hash_code(value: str) -> str:
    """정규화한 코드의 SHA-256. 코드가 80비트 난수라 소금 없이도 거꾸로 풀 수 없다."""
    return hashlib.sha256(normalize_code(value).encode("ascii", "ignore")).hexdigest()


def _joiner(part: str) -> str:
    """쿼리를 이어 붙일 구분자. 이미 `?`·`&` 로 끝나면 더 붙이지 않는다."""
    if part.endswith(("?", "&")):
        return ""
    return "&" if "?" in part else "?"


def reset_link(base_url: str, code: str) -> str:
    """설정한 화면 주소에 `token` 을 붙인다. 주소가 비면 빈 문자열(링크 없음).

    두 앱은 해시 URL 전략이라 화면 경로와 쿼리가 `#` 뒤에 있다
    (`https://<도메인>/trainer/#/auth/password-reset`, #3033). 주소에 `#` 가 있으면
    토큰을 **해시 안의 쿼리**에 붙인다 — 해시 앞에 쿼리가 있어도
    (`…/trainer/?ref=mail#/auth/password-reset`) 토큰이 앱이 읽는 자리로 간다.
    """
    base = base_url.strip()
    if not base:
        return ""
    token = urlencode({"token": code})
    head, hashed, fragment = base.partition("#")
    if hashed:
        return f"{head}#{fragment}{_joiner(fragment)}{token}"
    return f"{base}{_joiner(base)}{token}"


def reset_url_problem(url: str) -> str | None:
    """운영 재설정 화면 주소의 형식 문제(#3033). 비었거나 문제가 없으면 None.

    비어 있으면 메일에 코드만 보내는 정상 동작이다. 두 앱은 해시 URL 전략·하위 경로
    배포라 `#/` 가 없는 경로형 주소는 앱이 아닌 정적 경로를 가리켜 코드가 버려진다.
    """
    value = url.strip()
    if not value:
        return None
    parts = urlsplit(value)
    if parts.scheme.lower() != "https" or not parts.netloc:
        return "https:// 주소가 아님"
    if not parts.fragment.startswith("/"):
        return "해시 경로(#/auth/password-reset)가 없음"
    return None


def _link_base(settings: Settings, user: User) -> str:
    if user.role == "trainer":
        return settings.password_reset_trainer_url
    return settings.password_reset_member_url


def _compose(
    user: User, code: str, minutes: int, link: str, locale: Locale | None
) -> OutgoingMail:
    subject = localized(
        "[On-Care] 비밀번호 재설정 코드", "[On-Care] Your password reset code", locale
    )
    lines = [
        localized(
            "On-Care 비밀번호 재설정을 요청하셨습니다.",
            "We received a request to reset your On-Care password.",
            locale,
        ),
        "",
        localized("재설정 코드", "Reset code", locale) + f": {code}",
        localized(
            f"이 코드는 {minutes}분 동안 한 번만 쓸 수 있습니다.",
            f"The code works once and expires in {minutes} minutes.",
            locale,
        ),
    ]
    if link:
        lines += [
            "",
            localized(
                "아래 링크를 열어 새 비밀번호를 정할 수도 있습니다.",
                "You can also open this link to set a new password.",
                locale,
            ),
            link,
        ]
    lines += [
        "",
        localized(
            "직접 요청하지 않으셨다면 이 메일을 무시하세요. 비밀번호는 바뀌지 않습니다.",
            "If you didn't ask for this, ignore this email. Your password stays the same.",
            locale,
        ),
    ]
    return OutgoingMail(to=user.email, subject=subject, body="\n".join(lines))


def purge_expired(db: Session, *, now: datetime) -> int:
    """만료된 코드를 지운다. 쓰인 코드도 만료 뒤에는 남길 이유가 없다.

    커밋하지 않는다 — 호출부의 트랜잭션에 묶는다.
    """
    result = db.execute(
        delete(PasswordResetToken).where(PasswordResetToken.expires_at < now)
    )
    return int(result.rowcount or 0)


def _close_open_codes(db: Session, user_id: str, *, now: datetime) -> None:
    """이 계정의 아직 안 쓴 코드를 모두 닫는다."""
    db.execute(
        update(PasswordResetToken)
        .where(
            PasswordResetToken.user_id == user_id,
            PasswordResetToken.used_at.is_(None),
        )
        .values(used_at=now)
    )


def request_reset(
    db: Session,
    email: str,
    *,
    now: datetime,
    settings: Settings | None = None,
    mailer: Mailer | None = None,
    locale: Locale | None = None,
) -> IssuedReset | None:
    """재설정 코드를 만들어 보낸다. 보낼 계정이 없으면 None.

    서버가 메일을 보낼 수 없으면 [ResetUnavailable] — 계정 존재 여부와 무관한
    서버 상태라 응답에 드러내도 된다. 발송 실패는 던지지 않고 로그만 남긴다.
    """
    settings = settings or get_settings()
    if not settings.mail_enabled:
        raise ResetUnavailable()
    # 로그인과 같은 규칙으로 찾는다 — 키보드가 첫 글자를 대문자로 바꿔도 같은 계정이다
    # (#3094). 스키마를 거치지 않고 부르는 자리도 같은 결과가 나오게 여기서도 맞춘다.
    email = normalize_email(email)
    user = db.scalar(select(User).where(func.lower(User.email) == email))
    if user is None or not user.is_active:
        return None
    if not user.hashed_password:
        # 소셜 로그인 전용 계정에는 바꿀 비밀번호가 없다. 여기서 비밀번호를 만들어
        # 주면 소셜 계정에 이메일 로그인이 새로 열린다 — 그 결정은 #1551 의 몫이다.
        log.info("소셜 로그인 전용 계정이라 재설정 코드를 보내지 않음: %s", mask_email(email))
        return None

    purge_expired(db, now=now)
    # 새 코드를 보내면 앞서 보낸 코드는 닫는다 — 메일함에 살아 있는 코드가 여럿이면
    # 그중 어느 하나가 새어도 계정이 열린다.
    _close_open_codes(db, user.id, now=now)
    code = generate_code()
    expires_at = now + timedelta(minutes=settings.password_reset_token_minutes)
    db.add(
        PasswordResetToken(
            id=f"pwr-{uuid.uuid4().hex[:16]}",
            user_id=user.id,
            token_hash=hash_code(code),
            expires_at=expires_at,
        )
    )
    db.commit()

    mail = _compose(
        user,
        code,
        settings.password_reset_token_minutes,
        reset_link(_link_base(settings, user), code),
        locale,
    )
    try:
        (mailer or get_mailer(settings)).send(mail)
    except MailDeliveryError as exc:
        log.error("재설정 메일 발송 실패: to=%s err=%s", mask_email(email), exc)
    return IssuedReset(user_id=user.id, code=code, expires_at=expires_at)


def confirm_reset(
    db: Session, code: str, new_password: str, *, now: datetime
) -> User:
    """코드를 확인하고 비밀번호를 바꾼다. 쓸 수 없는 코드면 [InvalidResetCode].

    바꾼 계정의 토큰 세대를 올려 모든 기기의 세션을 끊는다(#2766). 비밀번호·세대·
    코드 사용 표시는 한 트랜잭션이다 — 하나만 반영되면 같은 코드로 다시 바꾸거나
    옛 세션이 살아남는다.
    """
    normalized = normalize_code(code)
    if len(normalized) != CODE_LENGTH:
        raise InvalidResetCode()
    row = db.scalar(
        select(PasswordResetToken).where(
            PasswordResetToken.token_hash == hash_code(normalized)
        )
    )
    if row is None or row.used_at is not None or row.expires_at <= now:
        raise InvalidResetCode()
    user = db.get(User, row.user_id)
    if user is None or not user.is_active:
        raise InvalidResetCode()
    user.hashed_password = hash_password(new_password)
    auth_tokens.bump_version(user)
    _close_open_codes(db, user.id, now=now)
    db.commit()
    return user
