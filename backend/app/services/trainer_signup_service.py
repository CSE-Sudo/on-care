"""트레이너 가입. (#475, #1627)

트레이너 계정을 만들 방법이 시드 스크립트뿐이었다. `/auth/register` 는 회원
전용이라 트레이너 앱에서 가입해도 `role='member'` 계정이 생기고 `/trainer/me` 가
403 을 돌려줬다 — 그래서 가입 진입점이 데모에서만 열려 있었다.

**소속은 가입 뒤에 정한다.** 처음에는 헬스장이 발급한 초대 코드가 소속을 결정했지만
발급 경로가 끝내 없어(#1627) 운영에서 새 트레이너를 받을 수 없었다. 초대 코드를
걷어 내고, 소속은 가입한 트레이너가 헬스장을 찾아 직접 고른다
(`PUT /trainer/me/gym`, #452). 소속을 정하기 전까지는 상담 대상이 아니다(#443·#451).
"""
from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.security import hash_password
from app.models.models import TrainerProfile, User
from app.schemas.user import TrainerRegister


class TrainerEmailTaken(Exception):
    """이미 가입된 이메일 — 409."""


def register_trainer(db: Session, payload: TrainerRegister) -> User:
    """트레이너 계정과 빈 프로필을 만든다.

    계정 생성·프로필 생성을 **한 트랜잭션**으로 커밋한다. 나눠 커밋하면 프로필 없는
    트레이너가 남아 `/trainer/me` 가 실패한다.
    """
    if db.scalar(select(User.id).where(User.email == payload.email)) is not None:
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

    db.add(TrainerProfile(trainer_id=trainer.id))

    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        # 이메일 유니크 제약만이 여기서 경합으로 터질 수 있다 — 트레이너 id 는
        # 새로 만든 UUID 다.
        raise TrainerEmailTaken("이미 가입된 이메일입니다.") from exc

    db.refresh(trainer)
    return trainer
