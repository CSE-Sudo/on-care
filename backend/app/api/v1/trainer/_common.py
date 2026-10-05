"""트레이너 라우터 공용 도우미 — 담당 고객·프로필 확인, 열람 감사, 날짜 형식 검사.

영역 라우터끼리 서로의 비공개 헬퍼를 직접 부르지 않고 이 모듈을 거친다(#2909).
"""
from __future__ import annotations

import re
from datetime import date as _date
from typing import Annotated

from fastapi import (
    Depends,
    HTTPException,
    Request,
)
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import RequireTrainer
from app.db.session import get_db
from app.models.models import (
    TrainerClient,
    TrainerProfile,
)
from app.services import (
    audit,
    data_consent_service,
)


# 계약 형식은 정확히 YYYY-MM-DD. date.fromisoformat 는 3.11+ 에서 basic ISO·주 날짜도 받으므로
# 정규식으로 먼저 좁힌 뒤 달력 유효성을 확인한다(schedule 라우트와 동일 규약).
_YMD_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def _is_ymd(v: str) -> bool:
    if not _YMD_RE.fullmatch(v):
        return False
    try:
        _date.fromisoformat(v)
        return True
    except ValueError:
        return False


def _require_profile(db: Session, trainer_id: str) -> TrainerProfile:
    profile = db.scalar(
        select(TrainerProfile).where(TrainerProfile.trainer_id == trainer_id)
    )
    if profile is None:
        raise HTTPException(status_code=404, detail="트레이너 프로필이 없습니다.")
    return profile


def _require_client(db: Session, trainer_id: str, member_id: str) -> TrainerClient:
    """(trainer, member) **살아 있는** 담당 링크를 확인한다. 없으면 404(소유권 경계).

    담당 해제는 행을 지우지 않고 `active=False` 로 내린다(`remove_client`). 행이
    있는지만 보면 해제된 회원의 식단·사진·채팅·루틴·메모·리포트·일정을 해제 뒤에도
    읽고 쓸 수 있으므로 `active` 까지 본다. (#2281)

    해제된 회원도 남의 회원·없는 회원과 **같은 404·같은 문구**다 — 다른 답을 주면
    "예전에 담당했던 회원" 이라는 사실이 응답만으로 드러난다. 해제된 링크를
    다뤄야 하는 곳(담당 해제 자체·재등록·활성/휴면 전환)은 이 함수를 쓰지 않고
    링크를 직접 읽는다.

    데이터 공유 동의가 철회된 뒤 새 동의 없이 살아 있는 링크도 같은 404 다
    (#1631). 담당 해제가 곧 동의 철회이고, 링크를 되살려도 회원의 새 동의가
    없으면 기록은 열리지 않는다.
    """
    link = db.scalar(
        select(TrainerClient).where(
            TrainerClient.trainer_id == trainer_id,
            TrainerClient.member_id == member_id,
        )
    )
    if not data_consent_service.link_is_open(link):
        raise HTTPException(status_code=404, detail="담당 회원을 찾을 수 없습니다.")
    return link


#: 열람 감사 대상 기록 종류(#2830). 트레이너가 만든 루틴·메모·채팅처럼 두 사람이
#: 함께 쓰는 기록은 넣지 않는다 — 회원이 남긴 건강정보를 읽는 경로만이다.
CLIENT_READ_RESOURCES = frozenset({"diet", "exercise", "body", "report"})


def _audit_client_read(resource: str):
    """회원 기록 조회 라우트에 붙이는 열람 감사 의존성(#2830).

    `dependencies=[_audit_client_read("diet")]` 처럼 붙인다. 라우트 본문이 쓰는
    [_require_client] 와 같은 기준(활성 링크·동의 유효)을 통과할 때만 남긴다 —
    남의 회원·해제된 회원 요청은 본문이 어차피 404 로 끝내므로 열람이 아니다.
    같은 (트레이너, 회원, 자원)은 설정한 시간 안에 한 번만 남기고(묶음 규칙),
    기록 실패는 조회를 막지 않는다. 기록 내용은 누가·누구의·무엇을·언제뿐이다.
    """
    if resource not in CLIENT_READ_RESOURCES:  # pragma: no cover - 개발 실수 방지
        raise ValueError(f"알 수 없는 열람 자원: {resource}")

    def dependency(
        member_id: str,
        request: Request,
        trainer: RequireTrainer,
        db: Annotated[Session, Depends(get_db)],
    ) -> None:
        link = db.scalar(
            select(TrainerClient).where(
                TrainerClient.trainer_id == trainer.id,
                TrainerClient.member_id == member_id,
            )
        )
        if (
            link is None
            or not link.active
            or data_consent_service.blocks_access(link)
        ):
            return
        audit.record_client_read(
            db,
            trainer_id=trainer.id,
            member_id=member_id,
            resource=resource,
            ip=audit.client_ip(request),
        )

    return Depends(dependency)
