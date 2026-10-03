"""운영자가 관리자 계정을 지정·해제한다. (#3037)

예전에는 기동할 때 `ADMIN_EMAILS` 에 적힌 주소의 계정을 관리자로 올렸다. 가입이
이메일 소유를 확인하지 않았으므로, 그 주소로 **먼저 가입한 사람**이 다음 배포 때
관리자가 됐다. 이제 관리자는 이 스크립트로만 바뀐다.

1. 이메일로 계정을 **찾기만** 한다(아무것도 바꾸지 않는다). id·역할·가입 시각·이메일
   확인 여부·소셜 연결을 보여 준다 — 운영자는 이 계정이 정말 그 사람의 것인지
   (본인에게 직접 확인한 id 인지) 보고 판단한다.
2. 바꾸려면 찾기에서 본 id 를 `--confirm-id` 로 **다시** 적는다. 이메일과 id 가
   같은 계정을 가리킬 때만 바꾼다 — 이메일만으로는 바꾸지 않는다.

대소문자만 다른 이메일 계정이 여럿이면 누구도 바꾸지 않는다(서버가 주인을 고를 수
없다). 지정·해제는 감사 로그(`admin.grant`·`admin.revoke`)에 대상 id 와 함께 남는다.
다른 관리자는 건드리지 않는다.

    python -m scripts.grant_admin --email ops@example.com                       # 찾기만
    python -m scripts.grant_admin --email ops@example.com --confirm-id u-1234    # 지정
    python -m scripts.grant_admin --email ops@example.com --confirm-id u-1234 --revoke

종료 코드: 0 성공(이미 그 상태 포함), 2 계정 없음, 3 대소문자 변형이 여럿, 4 id 불일치.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.models import SocialAccount, User
from app.services import audit

EXIT_OK = 0
EXIT_NOT_FOUND = 2
EXIT_AMBIGUOUS = 3
EXIT_MISMATCH = 4


class GrantError(Exception):
    """바꾸지 않고 끝낸다. `exit_code` 가 까닭이다."""

    def __init__(self, message: str, exit_code: int) -> None:
        super().__init__(message)
        self.exit_code = exit_code


@dataclass(frozen=True)
class AccountSummary:
    """운영자가 본인 계정인지 판단할 정보. 비밀번호·토큰은 담지 않는다."""

    id: str
    email: str
    role: str
    is_admin: bool
    is_active: bool
    created_at: str
    email_verified: bool
    social_providers: tuple[str, ...]


def find_account(db: Session, email: str) -> User:
    """이메일(대소문자 무시)로 계정 하나를 찾는다. 없거나 여럿이면 [GrantError]."""
    normalized = email.strip().lower()
    users = db.scalars(
        select(User).where(func.lower(User.email) == normalized)
    ).all()
    if not users:
        raise GrantError(f"{normalized} 계정이 없습니다.", EXIT_NOT_FOUND)
    if len(users) > 1:
        ids = ", ".join(sorted(u.id for u in users))
        raise GrantError(
            f"{normalized} 와 대소문자만 다른 계정이 여럿입니다({ids}) — 바꾸지 않습니다.",
            EXIT_AMBIGUOUS,
        )
    return users[0]


def summarize(db: Session, user: User) -> AccountSummary:
    providers = db.scalars(
        select(SocialAccount.provider).where(SocialAccount.user_id == user.id)
    ).all()
    return AccountSummary(
        id=user.id,
        email=user.email,
        role=user.role,
        is_admin=bool(user.is_admin),
        is_active=bool(user.is_active),
        created_at=user.created_at.isoformat() if user.created_at else "",
        email_verified=user.email_verified_at is not None,
        social_providers=tuple(sorted(providers)),
    )


def set_admin(
    db: Session, *, email: str, confirm_id: str, grant: bool
) -> tuple[User, bool]:
    """이메일과 id 가 같은 계정이면 관리자 여부를 바꾸고 커밋한다.

    돌려주는 값은 (계정, 실제로 바뀌었는가). 이미 그 상태면 감사 기록 없이 그대로 둔다.
    바뀐 값과 감사 기록은 한 트랜잭션이다.
    """
    user = find_account(db, email)
    if user.id != confirm_id.strip():
        raise GrantError(
            f"--confirm-id({confirm_id.strip()})가 {user.email} 계정 id({user.id})와 "
            "다릅니다 — 바꾸지 않습니다.",
            EXIT_MISMATCH,
        )
    if bool(user.is_admin) == grant:
        return user, False
    user.is_admin = grant
    audit.stage(
        db,
        event=audit.ADMIN_GRANT if grant else audit.ADMIN_REVOKE,
        target_user_id=user.id,
        detail="via=script",
    )
    db.commit()
    return user, True


def _print_summary(summary: AccountSummary) -> None:
    print(f"id: {summary.id}")
    print(f"이메일: {summary.email}")
    print(f"역할: {summary.role}  활성: {summary.is_active}  관리자: {summary.is_admin}")
    print(f"가입: {summary.created_at}")
    print(f"이메일 확인: {'예' if summary.email_verified else '아니오(확인 절차 이전 가입)'}")
    print(f"소셜 연결: {', '.join(summary.social_providers) or '없음'}")


def main(argv: list[str] | None = None) -> int:
    from app.db.session import SessionLocal

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--email", required=True, help="찾을 계정의 이메일")
    parser.add_argument(
        "--confirm-id",
        default="",
        help="찾기에서 본 계정 id. 이 값이 있어야 바꾼다.",
    )
    parser.add_argument(
        "--revoke", action="store_true", help="지정 대신 관리자를 해제한다."
    )
    args = parser.parse_args(argv)

    db = SessionLocal()
    try:
        try:
            user = find_account(db, args.email)
            _print_summary(summarize(db, user))
            if not args.confirm_id.strip():
                print(
                    "찾기만 했습니다 — 바꾸려면 위 id 를 본인에게 확인한 뒤 "
                    "--confirm-id 로 다시 적으십시오."
                )
                return EXIT_OK
            user, changed = set_admin(
                db, email=args.email, confirm_id=args.confirm_id, grant=not args.revoke
            )
        except GrantError as exc:
            print(str(exc))
            return exc.exit_code
        action = "해제" if args.revoke else "지정"
        if changed:
            print(f"{user.email}({user.id}) 관리자 {action}했습니다.")
        else:
            print(f"이미 그 상태입니다 — 바꾸지 않았습니다({action}).")
        return EXIT_OK
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
