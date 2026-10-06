"""가입 이메일 확인 코드(#3038) — 가입하는 사람이 그 주소의 주인인지 확인한다.

예전 가입은 이메일 형식만 봤다. 남의 주소로 먼저 가입하면 그 주소의 계정을 차지하고,
그 주소를 믿는 기능(관리자 지정 #3037, 비밀번호 재설정 메일, 소셜 자동 연결 #1551)이
가입한 사람 편이 됐다. 이제 계정을 만들기 **전에** 그 주소로 보낸 6자리 코드를 받는다.

1. **요청** — (이메일, 용도)로 코드를 만들어 메일로 보낸다. 이미 가입된 주소에는 코드
   대신 "이미 계정이 있다"는 안내를 보낸다. 호출부는 어느 쪽이든 **같은 응답**을 준다
   — 응답이 다르면 아무 주소나 넣어 가입 여부를 알아낼 수 있다.
2. **확인** — 가입 요청이 코드를 가져오면 가장 최근 코드와 비교한다. 맞으면 쓴 것으로
   표시한다(커밋은 계정 생성과 한 트랜잭션). 틀리면 실패 횟수를 바로 커밋한다 —
   가입이 실패해도 횟수는 남아야 한다. 상한에 닿은 코드는 더 받지 않는다. 횟수는
   비교 전에 DB 에서 원자적으로 올린다(#3238).

코드는 계정이 아니라 (소문자 이메일, 용도)에 묶인다. 회원 가입 코드로 트레이너
가입을 할 수 없고, 화면에서 이메일을 바꾸면 새 코드가 필요하다.

로그인 이메일 변경(#3230)도 같은 코드를 쓴다(용도 `email_change`). 바꿀 새 주소로 코드를
보내고, 그 코드를 가져와야 이메일이 바뀐다 — 남의 주소로 바꿔 그 주소를 선점하거나
그 주소의 소셜 로그인을 자기 계정으로 끌어오지 못하게 한다. 표에는 서버 비밀값
(`JWT_SECRET`)으로 만든 HMAC 만 남긴다 — 6자리는 경우의 수가 백만뿐이라 소금 없는
해시는 표가 새면 곧바로 풀린다.
"""
from __future__ import annotations

import hashlib
import hmac
import logging
import secrets
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import delete, func, select, update
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.locale import Locale, localized
from app.models.models import EmailVerificationCode, User
from app.services.account_notice import support_lines
from app.services.mailer import (
    Mailer,
    MailDeliveryError,
    OutgoingMail,
    get_mailer,
    mask_email,
)

log = logging.getLogger(__name__)

MEMBER_SIGNUP = "member_signup"
TRAINER_SIGNUP = "trainer_signup"
#: 로그인 이메일 변경(#3230). 가입 코드 요청(`POST /auth/register/email-code`)으로는
#: 받을 수 없고 로그인한 회원의 `POST /users/me/email/code` 로만 받는다.
EMAIL_CHANGE = "email_change"
#: 받는 용도. 값은 API 계약(`purpose`)이다.
PURPOSES: frozenset[str] = frozenset({MEMBER_SIGNUP, TRAINER_SIGNUP, EMAIL_CHANGE})
#: 코드 자릿수.
CODE_LENGTH = 6


class CodeUnavailable(Exception):
    """이 서버는 확인 메일을 보낼 수 없다(운영인데 발송 설정이 없음)."""


class InvalidEmailCode(Exception):
    """코드가 없거나, 틀렸거나, 만료됐거나, 이미 쓰였다. 어느 쪽인지는 밝히지 않는다."""


@dataclass(frozen=True)
class IssuedCode:
    """요청이 실제로 만든 코드. 이미 가입된 주소면 만들지 않는다 — 테스트용 값이다."""

    email: str
    purpose: str
    code: str
    expires_at: datetime


def generate_code() -> str:
    """6자리 숫자 코드. 앞자리 0 도 그대로 둔다."""
    return f"{secrets.randbelow(10**CODE_LENGTH):0{CODE_LENGTH}d}"


def normalize_code(value: str) -> str:
    """사람이 친 코드에서 숫자만 남긴다(공백·하이픈은 보지 않는다)."""
    return "".join(ch for ch in value if ch.isdigit())


def hash_code(email: str, purpose: str, code: str, *, settings: Settings) -> str:
    """(이메일, 용도, 코드)의 HMAC-SHA256. 같은 코드라도 주소·용도가 다르면 다른 값."""
    message = f"{purpose}\n{email.lower()}\n{normalize_code(code)}".encode()
    return hmac.new(settings.jwt_secret.encode(), message, hashlib.sha256).hexdigest()


def purge_stale(db: Session, *, now: datetime) -> int:
    """만료된 코드를 지운다. 커밋하지 않는다 — 호출부의 트랜잭션에 묶는다."""
    result = db.execute(
        delete(EmailVerificationCode).where(EmailVerificationCode.expires_at < now)
    )
    return int(result.rowcount or 0)


def _close_open_codes(db: Session, email: str, purpose: str, *, now: datetime) -> None:
    """이 (이메일, 용도)의 아직 안 쓴 코드를 모두 닫는다."""
    db.execute(
        update(EmailVerificationCode)
        .where(
            EmailVerificationCode.email == email,
            EmailVerificationCode.purpose == purpose,
            EmailVerificationCode.used_at.is_(None),
        )
        .values(used_at=now)
    )


def _compose_code(
    email: str,
    code: str,
    minutes: int,
    settings: Settings,
    locale: Locale | None,
    purpose: str = MEMBER_SIGNUP,
) -> OutgoingMail:
    subject = localized(
        "[On-Care] 이메일 인증 코드", "[On-Care] Your email verification code", locale
    )
    changing = purpose == EMAIL_CHANGE
    lead = (
        localized(
            "On-Care 로그인 이메일을 이 주소로 바꾸기 위한 인증 코드를 보내 드립니다.",
            "Here is the code to make this address your On-Care sign-in email.",
            locale,
        )
        if changing
        else localized(
            "On-Care 가입을 위해 이메일 인증 코드를 보내 드립니다.",
            "Here is the code to verify your email for your On-Care sign-up.",
            locale,
        )
    )
    ignore = (
        localized(
            "직접 요청하지 않으셨다면 이 메일을 무시하세요. 어떤 계정의 이메일도 이 주소로 "
            "바뀌지 않습니다.",
            "If you didn't ask for this, ignore this email. No account will switch to "
            "this address.",
            locale,
        )
        if changing
        else localized(
            "직접 가입하지 않으셨다면 이 메일을 무시하세요. 계정이 만들어지지 않습니다.",
            "If you didn't try to sign up, ignore this email. No account will be created.",
            locale,
        )
    )
    lines = [
        lead,
        "",
        localized("인증 코드", "Verification code", locale) + f": {code}",
        localized(
            f"이 코드는 {minutes}분 동안 한 번만 쓸 수 있습니다.",
            f"The code works once and expires in {minutes} minutes.",
            locale,
        ),
        "",
        ignore,
    ]
    lines += support_lines(settings, locale)
    return OutgoingMail(to=email, subject=subject, body="\n".join(lines))


def _compose_already_registered(
    email: str, settings: Settings, locale: Locale | None, purpose: str = MEMBER_SIGNUP
) -> OutgoingMail:
    subject = localized(
        "[On-Care] 이미 가입된 이메일입니다", "[On-Care] You already have an account", locale
    )
    asked = (
        localized(
            "다른 On-Care 계정의 로그인 이메일을 이 주소로 바꾸려는 인증 코드 요청이 "
            "들어왔지만, 이 주소로는 이미 계정이 있어 바꿀 수 없습니다.",
            "Someone asked for a code to switch another On-Care account to this email, "
            "but an account already uses this address, so it can't be switched.",
            locale,
        )
        if purpose == EMAIL_CHANGE
        else localized(
            "이 이메일로 On-Care 가입 인증 코드 요청이 들어왔지만, 이 주소로는 이미 "
            "계정이 있습니다.",
            "Someone asked for an On-Care sign-up code for this email, but an account "
            "already uses this address.",
            locale,
        )
    )
    lines = [
        asked,
        localized(
            "본인이라면 로그인하시고, 비밀번호가 기억나지 않으면 로그인 화면에서 "
            "비밀번호 재설정을 이용하세요.",
            "If this was you, sign in instead. Forgot your password? Use password reset "
            "on the sign-in screen.",
            locale,
        ),
        "",
        localized(
            "직접 요청하지 않으셨다면 이 메일을 무시하세요. 계정은 그대로입니다.",
            "If you didn't ask for this, ignore this email. Your account is unchanged.",
            locale,
        ),
    ]
    lines += support_lines(settings, locale)
    return OutgoingMail(to=email, subject=subject, body="\n".join(lines))


def request_code(
    db: Session,
    email: str,
    purpose: str,
    *,
    now: datetime,
    settings: Settings | None = None,
    mailer: Mailer | None = None,
    locale: Locale | None = None,
) -> IssuedCode | None:
    """코드를 만들어 보낸다. 이미 가입된 주소면 안내만 보내고 None.

    `email` 은 정규화(소문자)된 값이다. 서버가 메일을 보낼 수 없으면 [CodeUnavailable]
    — 주소와 무관한 서버 상태라 응답에 드러내도 된다. 발송 실패는 던지지 않고 로그만
    남긴다(응답이 갈리지 않게).
    """
    settings = settings or get_settings()
    if not settings.mail_enabled:
        raise CodeUnavailable()
    if purpose not in PURPOSES:
        raise ValueError(f"unknown purpose: {purpose}")
    sender = mailer or get_mailer(settings)

    registered = db.scalar(
        select(User.id).where(func.lower(User.email) == email.lower())
    )
    if registered is not None:
        try:
            sender.send(_compose_already_registered(email, settings, locale, purpose))
        except MailDeliveryError as exc:
            log.error("가입 안내 메일 발송 실패: to=%s err=%s", mask_email(email), exc)
        return None

    purge_stale(db, now=now)
    # 새 코드를 보내면 앞서 보낸 코드는 닫는다 — 살아 있는 코드가 여럿이면 맞힐 확률이
    # 그만큼 커진다.
    _close_open_codes(db, email, purpose, now=now)
    code = generate_code()
    expires_at = now + timedelta(minutes=settings.signup_email_code_minutes)
    db.add(
        EmailVerificationCode(
            id=f"evc-{uuid.uuid4().hex[:16]}",
            email=email,
            purpose=purpose,
            code_hash=hash_code(email, purpose, code, settings=settings),
            expires_at=expires_at,
        )
    )
    db.commit()
    try:
        sender.send(
            _compose_code(
                email, code, settings.signup_email_code_minutes, settings, locale, purpose
            )
        )
    except MailDeliveryError as exc:
        log.error("가입 인증 메일 발송 실패: to=%s err=%s", mask_email(email), exc)
    return IssuedCode(email=email, purpose=purpose, code=code, expires_at=expires_at)


def consume(
    db: Session,
    email: str,
    purpose: str,
    code: str,
    *,
    now: datetime,
    settings: Settings | None = None,
) -> None:
    """가장 최근 코드와 비교해 맞으면 쓴 것으로 표시한다(커밋은 호출부).

    맞지 않으면 [InvalidEmailCode] 이고 실패 횟수는 **커밋된 채** 남는다 — 호출부는
    이 예외 뒤에 계정을 만들지 않으므로 커밋할 다른 변경이 없다. 횟수가 상한에 닿은
    코드, 만료·사용된 코드, 다른 용도의 코드는 모두 같은 예외다.

    시도 한 번은 비교하기 **전에** DB 에서 한 문장으로 센다(#3238). 예전에는 횟수를
    읽어 파이썬에서 `+= 1` 했다 — 동시에 온 요청이 같은 값을 읽고 서로의 증가분을
    덮어써, 한 번에 여러 개를 보내면 코드 한 장당 상한이 무력해졌다. 이제 상한 아래인
    행만 올리는 `UPDATE … WHERE attempts < 상한` 이라, 행 잠금이 요청을 줄 세우고 한
    코드로 비교에 들어가는 요청은 상한을 넘지 않는다. 맞힌 시도도 하나로 세지만, 그
    코드는 쓴 것으로 닫히므로 더 셀 일이 없다.
    """
    settings = settings or get_settings()
    normalized = normalize_code(code)
    row = db.execute(
        select(EmailVerificationCode.id, EmailVerificationCode.code_hash)
        .where(
            EmailVerificationCode.email == email.lower(),
            EmailVerificationCode.purpose == purpose,
            EmailVerificationCode.used_at.is_(None),
        )
        .order_by(EmailVerificationCode.created_at.desc(), EmailVerificationCode.id.desc())
        .limit(1)
    ).first()
    if row is None:
        raise InvalidEmailCode()
    claimed = db.execute(
        update(EmailVerificationCode)
        .where(
            EmailVerificationCode.id == row.id,
            EmailVerificationCode.used_at.is_(None),
            EmailVerificationCode.expires_at > now,
            EmailVerificationCode.attempts < settings.signup_email_code_max_attempts,
        )
        .values(attempts=EmailVerificationCode.attempts + 1)
        .execution_options(synchronize_session=False)
    )
    if not claimed.rowcount:
        # 만료·사용됐거나 상한에 닿았다. 걸린 행이 없어 잠근 것도 바꾼 것도 없다.
        raise InvalidEmailCode()
    expected = hash_code(email, purpose, normalized, settings=settings)
    if len(normalized) != CODE_LENGTH or not hmac.compare_digest(row.code_hash, expected):
        db.commit()
        raise InvalidEmailCode()
    db.execute(
        update(EmailVerificationCode)
        .where(EmailVerificationCode.id == row.id)
        .values(used_at=now)
        .execution_options(synchronize_session=False)
    )
