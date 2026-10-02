"""트레이너 가입. (#475, #1627)

트레이너 계정을 만들 방법이 시드 스크립트뿐이었다. `/auth/register` 는 회원
전용이라 트레이너 앱에서 가입해도 `role='member'` 계정이 생기고 `/trainer/me` 가
403 을 돌려줬다 — 그래서 가입 진입점이 데모에서만 열려 있었다.

**소속은 가입 뒤에 정한다.** 처음에는 헬스장이 발급한 초대 코드가 소속을 결정했지만
발급 경로가 끝내 없어(#1627) 운영에서 새 트레이너를 받을 수 없었다. 초대 코드를
걷어 내고, 소속은 가입한 트레이너가 헬스장을 찾아 직접 고른다
(`PUT /trainer/me/gym`, #452). 소속을 정하기 전까지는 상담 대상이 아니다(#443·#451).

**운영자 승인 전에는 노출되지 않는다(#2825).** 가입은 누구나 할 수 있고 소속도
직접 고르므로, 가입한 트레이너는 pending 으로 시작한다. 승인 전까지 회원 앱
디렉터리·상담 대상·담당 요청·연결 코드에서 빠진다(`trainer_verification_service`).
"""
from __future__ import annotations

import uuid

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.security import hash_password
from app.models.models import TrainerProfile, User
from app.schemas.user import TrainerRegister
from app.services import signup_consent
from app.services import trainer_verification_service


class TrainerEmailTaken(Exception):
    """이미 가입된 이메일 — 409."""


def register_trainer(db: Session, payload: TrainerRegister) -> User:
    """트레이너 계정과 빈 프로필, 가입 동의 기록을 만든다.

    계정 생성·프로필 생성을 **한 트랜잭션**으로 커밋한다. 나눠 커밋하면 프로필 없는
    트레이너가 남아 `/trainer/me` 가 실패한다.
    """
    # 스키마가 소문자로 맞춘 값이다. 대소문자만 다른 기존 주소도 같은 이메일(#2816).
    taken = db.scalar(select(User.id).where(func.lower(User.email) == payload.email))
    if taken is not None:
        raise TrainerEmailTaken("이미 가입된 이메일입니다.")

    trainer = User(
        id=f"trainer-{uuid.uuid4().hex[:12]}",
        email=payload.email,
        name=payload.name or payload.email.split("@")[0],
        hashed_password=hash_password(payload.password),
        role="trainer",
    )
    db.add(trainer)
    db.flush()

    # 모델 기본값(approved)은 운영자가 직접 넣는 시드 경로용이다 — 공개 가입은
    # 승인 대기를 명시한다(#2825).
    db.add(
        TrainerProfile(
            trainer_id=trainer.id,
            verification_status=trainer_verification_service.PENDING,
        )
    )
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
