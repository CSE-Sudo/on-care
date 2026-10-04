"""트레이너 가입. (#475, #1627)

트레이너 계정을 만들 방법이 시드 스크립트뿐이었다. `/auth/register` 는 회원
전용이라 트레이너 앱에서 가입해도 `role='member'` 계정이 생기고 `/trainer/me` 가
403 을 돌려줬다 — 그래서 가입 진입점이 데모에서만 열려 있었다.

**소속은 가입 뒤에 정한다.** 처음에는 헬스장이 발급한 초대 코드가 소속을 결정했지만
발급 경로가 끝내 없어(#1627) 운영에서 새 트레이너를 받을 수 없었다. 초대 코드를
걷어 내고, 소속은 가입한 트레이너가 헬스장을 찾아 직접 고른다
(`PUT /trainer/me/gym`, #452). 소속을 정하기 전까지는 상담 대상이 아니다(#443·#451).

**운영자 승인 단계는 없다(#3008).** 소속 헬스장을 고르면 바로 회원 앱에 나오고
회원을 연결할 수 있다. 회원 신고와 운영자의 계정 정지가 사후 관리 경로다.
"""
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.security import hash_password
from app.models.models import TrainerProfile, User
from app.schemas.user import TrainerRegister
from app.services import signup_consent


class TrainerEmailTaken(Exception):
    """이미 가입된 이메일 — 409."""


def ensure_email_available(db: Session, email: str) -> None:
    """이미 가입된 이메일이면 [TrainerEmailTaken].

    스키마가 소문자로 맞춘 값이다. 대소문자만 다른 기존 주소도 같은 이메일(#2816).
    라우터가 가입 인증 코드를 확인하기 **전에** 부른다(#3038) — 409 가 400 보다 먼저다.
    """
    taken = db.scalar(select(User.id).where(func.lower(User.email) == email))
    if taken is not None:
        raise TrainerEmailTaken("이미 가입된 이메일입니다.")


def register_trainer(
    db: Session,
    payload: TrainerRegister,
    *,
    email_verified_at: datetime | None = None,
) -> User:
    """트레이너 계정과 빈 프로필, 가입 동의 기록을 만든다.

    계정 생성·프로필 생성을 **한 트랜잭션**으로 커밋한다. 나눠 커밋하면 프로필 없는
    트레이너가 남아 `/trainer/me` 가 실패한다. 라우터가 가입 인증 코드를 쓴 것으로
    표시해 두었다면(#3038) 그 표시도 같은 커밋이다 — 가입이 실패하면 코드도 살아 있다.
    """
    ensure_email_available(db, payload.email)

    trainer = User(
        id=f"trainer-{uuid.uuid4().hex[:12]}",
        email=payload.email,
        email_verified_at=email_verified_at,
        name=payload.name or payload.email.split("@")[0],
        hashed_password=hash_password(payload.password),
        role="trainer",
    )
    db.add(trainer)
    db.flush()

    db.add(TrainerProfile(trainer_id=trainer.id))
    # 가입 화면에서 체크한 동의도 같은 트랜잭션이다(#2819). 목록을 보내지 않은
    # 옛 빌드는 기록 없이 만들어지고, 로그인 직후 동의 화면을 거친다.
    if payload.consents is not None:
        signup_consent.record(db, trainer.id, payload.consents)

    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        # 이메일 유니크 제약만이 여기서 경합으로 터질 수 있다 — 트레이너 id 는
        # 새로 만든 UUID 다.
        raise TrainerEmailTaken("이미 가입된 이메일입니다.") from exc

    db.refresh(trainer)
    return trainer
