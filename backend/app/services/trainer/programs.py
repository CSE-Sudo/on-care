"""트레이너 도메인 — 프로그램 초안. (#708)"""
from __future__ import annotations

import json
import uuid
from collections.abc import Sequence
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.models import (
    TrainerProgramDraft,
)
from app.schemas.trainer_api import (
    ProgramDraftSession,
    TrainerProgramDraftOut, TrainerProgramDraftSummary,
)
from app.services.trainer._common import (
    _validated_exercises,
)


# ---- 프로그램 초안 (#708) ----


class ProgramDraftNotFound(Exception):
    """그 트레이너에게 그 id 의 초안이 없다(라우터가 404 로 변환)."""


def draft_sessions(sessions_json: str) -> list[ProgramDraftSession]:
    """저장된 세션 목록을 순서 그대로 읽는다. (#709)

    운동과 같은 이유로 관대하다 — 읽을 수 없는 세션 하나가 프로그램 전체를
    못 열게 만들면 안 된다.
    """
    try:
        raw = json.loads(sessions_json) if sessions_json else []
    except json.JSONDecodeError:
        return []
    if not isinstance(raw, list):
        return []
    out: list[ProgramDraftSession] = []
    for index, item in enumerate(raw):
        if not isinstance(item, dict):
            continue
        out.append(
            ProgramDraftSession(
                id=str(item.get("id") or f"session-{index + 1}"),
                name=str(item.get("name") or ""),
                exercises=_validated_exercises(item.get("exercises")),
            )
        )
    return out


def dump_draft_sessions(sessions: Sequence[ProgramDraftSession]) -> str:
    # mode="json" 이라야 날짜가 문자열로 나간다 — 파이썬 date 는 json 이 모른다.
    return json.dumps(
        [session.model_dump(mode="json") for session in sessions], ensure_ascii=False
    )


def draft_workspace(workspace_json: str) -> dict:
    """자동 보관한 작성 상태를 읽는다(#2873). 깨진 값이면 빈 객체다.

    세션과 같은 이유로 관대하다 — 작성 상태를 못 읽어도 편집기 구성은 열려야
    한다.
    """
    try:
        raw = json.loads(workspace_json) if workspace_json else {}
    except json.JSONDecodeError:
        return {}
    return raw if isinstance(raw, dict) else {}


def _dump_workspace(workspace: dict | None) -> str:
    return json.dumps(workspace or {}, ensure_ascii=False)


def _draft_out(draft: TrainerProgramDraft) -> TrainerProgramDraftOut:
    return TrainerProgramDraftOut(
        id=draft.id,
        name=draft.name,
        goal=draft.goal,
        period=draft.period,
        memo=draft.memo,
        sessions=draft_sessions(draft.sessions_json),
        member_id=draft.member_id,
        workspace=draft_workspace(draft.workspace_json),
        created_at=draft.created_at,
        updated_at=draft.updated_at,
    )


#: 목록이 한 번에 내려주는 최대 초안 수. 초안은 지우지 않으면 쌓이기만 한다.
_PROGRAM_DRAFT_LIMIT = 100


def build_program_drafts(
    db: Session, trainer_id: str, member_id: str | None = None
) -> list[TrainerProgramDraftSummary]:
    """내가 저장한 프로그램 초안 목록(최근 수정 먼저).

    세션·운동 구성은 싣지 않는다 — 목록은 "무엇을 저장해 뒀나"만 보여 주고,
    편집기로 불러올 때 상세를 따로 읽는다.

    [member_id] 를 주면 그 회원에게 자동 보관한 것만 돌려준다(#2873) — 코칭
    화면이 그 회원의 작성 중 내용을 찾는 길이다.
    """
    query = select(TrainerProgramDraft).where(
        TrainerProgramDraft.trainer_id == trainer_id
    )
    if member_id is not None:
        query = query.where(TrainerProgramDraft.member_id == member_id)
    rows = db.scalars(
        query
        .order_by(
            TrainerProgramDraft.updated_at.desc(), TrainerProgramDraft.id.desc()
        )
        .limit(_PROGRAM_DRAFT_LIMIT)
    ).all()
    out: list[TrainerProgramDraftSummary] = []
    for d in rows:
        sessions = draft_sessions(d.sessions_json)
        out.append(
            TrainerProgramDraftSummary(
                id=d.id,
                name=d.name,
                goal=d.goal,
                period=d.period,
                session_count=len(sessions),
                exercise_count=sum(len(s.exercises) for s in sessions),
                member_id=d.member_id,
                updated_at=d.updated_at,
            )
        )
    return out


def _owned_draft(
    db: Session, trainer_id: str, draft_id: str
) -> TrainerProgramDraft:
    """내가 저장한 초안만 집는다. 남의 초안과 없는 초안은 똑같이 404 다."""
    draft = db.scalar(
        select(TrainerProgramDraft).where(
            TrainerProgramDraft.id == draft_id,
            TrainerProgramDraft.trainer_id == trainer_id,
        )
    )
    if draft is None:
        raise ProgramDraftNotFound("저장된 프로그램을 찾을 수 없습니다.")
    return draft


def get_program_draft(
    db: Session, trainer_id: str, draft_id: str
) -> TrainerProgramDraftOut:
    return _draft_out(_owned_draft(db, trainer_id, draft_id))


def create_program_draft(
    db: Session, trainer_id: str, *,
    name: str, goal: str, period: str, memo: str,
    sessions: Sequence[ProgramDraftSession],
    member_id: str | None = None,
    workspace: dict | None = None,
) -> TrainerProgramDraftOut:
    """프로그램 초안을 저장한다. 세션은 받은 순서 그대로 남는다.

    [member_id] 가 있으면 코칭 화면이 그 회원에게 짜던 내용을 자동 보관한
    것이다(#2873). 담당 회원인지는 라우터가 먼저 확인한다.
    """
    now = datetime.now(timezone.utc)
    draft = TrainerProgramDraft(
        id=f"pgm-{uuid.uuid4().hex[:12]}",
        trainer_id=trainer_id,
        name=name,
        goal=goal,
        period=period,
        memo=memo,
        sessions_json=dump_draft_sessions(sessions),
        member_id=member_id,
        workspace_json=_dump_workspace(workspace),
        created_at=now,
        updated_at=now,
    )
    db.add(draft)
    db.commit()
    db.refresh(draft)
    return _draft_out(draft)


def update_program_draft(
    db: Session, trainer_id: str, draft_id: str, fields: dict
) -> TrainerProgramDraftOut:
    """저장된 초안을 고친다. 보낸 필드만 반영한다.

    `sessions` 는 통째로 교체한다 — 편집기가 항목 단위 diff 가 아니라 현재
    구성 전체를 들고 있다.
    """
    draft = _owned_draft(db, trainer_id, draft_id)
    for field in ("name", "goal", "period", "memo"):
        if field in fields:
            setattr(draft, field, fields[field])
    if "sessions" in fields:
        draft.sessions_json = dump_draft_sessions(
            [
                item
                if isinstance(item, ProgramDraftSession)
                else ProgramDraftSession.model_validate(item)
                for item in fields["sessions"]
            ]
        )
    if "workspace" in fields:
        draft.workspace_json = _dump_workspace(fields["workspace"])
    draft.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(draft)
    return _draft_out(draft)


def delete_program_draft(db: Session, trainer_id: str, draft_id: str) -> None:
    """저장된 초안을 지운다. 배정된 루틴·스케줄은 건드리지 않는다 —
    초안에서 만들어진 뒤로는 서로 독립적인 데이터다."""
    draft = _owned_draft(db, trainer_id, draft_id)
    db.delete(draft)
    db.commit()
