"""트레이너별 프로그램 템플릿. (#920)

템플릿은 "어느 회원에게든 끼워 넣는 블록"이다. 초안
(`trainer.programs.*_program_draft`)이 답하는 "이 회원에게 짜 둔 프로그램"과는
다른 질문이라, 세션 없이 운동 목록 하나만 갖는다.

**저장된 템플릿이 없는 트레이너에게는 서버가 시작 구성을 돌려준다.** 빈 화면으로
시작하면 이 기능이 무엇인지 알 수 없기 때문이다. 시작 구성은 저장된 행이 아니라
읽을 때 만들어지는 값이고(`id` 가 `starter:` 로 시작한다), 고치거나 지울 수 없다 —
편집하면 그 트레이너의 첫 템플릿으로 **새로 저장된다.** 그래서 "지웠는데 되살아
난다" 가 생기지 않는다: 하나라도 자기 것이 생기는 순간 시작 구성은 사라진다.

시작 구성은 저장된 값이 아니라 읽을 때 만드는 값이라 **요청 언어로 만든다**
(#2301). 트레이너가 저장한 템플릿은 트레이너가 쓴 글이라 옮기지 않는다 — 영어
화면에서 시작 구성을 고쳐 저장하면 영어 템플릿으로 남는다.
"""
from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.locale import Locale, current_locale
from app.models.models import TrainerProgramTemplate
from app.schemas.trainer_api import (
    ProgramTemplateExercise,
    TrainerProgramTemplateOut,
)

#: 한 트레이너가 저장할 수 있는 템플릿 수. 고르는 목록이라 길어지면 고르기가
#: 어려워진다 — 초안(저장고)과 다른 성격이다.
TEMPLATE_LIMIT = 30

#: 읽기 전용 시작 구성의 id 접두사. 저장된 행과 섞이지 않게 갈라 둔다.
STARTER_PREFIX = "starter:"

#: 저장된 템플릿이 없을 때 보여 주는 시작 구성.
#:
#: 앱에 하드코딩돼 있던 셋을 그대로 옮겼다 — 이 기능이 생기기 전에 트레이너들이
#: 보던 것과 같아야, 바뀐 것은 "고칠 수 있게 됐다" 하나가 된다.
_STARTERS: tuple[tuple[str, str, tuple[tuple[str, int, str], ...]], ...] = (
    (
        "혈압 관리 기본",
        "혈압 관리 · 초급",
        (
            ("준비 스트레칭", 10, "스트레칭"),
            ("저강도 걷기", 20, "유산소"),
            ("호흡 이완", 10, "스트레칭"),
        ),
    ),
    (
        "체중 감량 순환",
        "체중 감량 · 중급",
        (
            ("인터벌 유산소", 20, "유산소"),
            ("전신 서킷", 20, "근력"),
            ("마무리 스트레칭", 10, "스트레칭"),
        ),
    ),
    (
        "하체 근력 A",
        "근력 향상 · 중급",
        (
            ("레그프레스", 15, "근력"),
            ("루마니안 데드리프트", 15, "근력"),
            ("카프 레이즈", 10, "근력"),
        ),
    ),
)

#: [_STARTERS] 의 영어판(#2301). 순서·시간·유형은 같고 이름·목표만 다르다 —
#: 같은 `starter:N` 이 언어마다 다른 운동이 되면 안 된다.
_STARTERS_EN: tuple[tuple[str, str, tuple[tuple[str, int, str], ...]], ...] = (
    (
        "Blood pressure basics",
        "Blood pressure care · Beginner",
        (
            ("Warm-up stretch", 10, "스트레칭"),
            ("Low-intensity walk", 20, "유산소"),
            ("Breathing & relaxation", 10, "스트레칭"),
        ),
    ),
    (
        "Weight-loss circuit",
        "Weight loss · Intermediate",
        (
            ("Interval cardio", 20, "유산소"),
            ("Full-body circuit", 20, "근력"),
            ("Cool-down stretch", 10, "스트레칭"),
        ),
    ),
    (
        "Lower-body strength A",
        "Strength building · Intermediate",
        (
            ("Leg press", 15, "근력"),
            ("Romanian deadlift", 15, "근력"),
            ("Calf raise", 10, "근력"),
        ),
    ),
)


class TemplateNotFound(Exception):
    """없거나 남의 템플릿이다. 둘을 구분하지 않는다."""


class TemplateLimitReached(Exception):
    """저장 한도에 닿았다."""


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _exercises(raw: str) -> list[ProgramTemplateExercise]:
    """저장된 JSON 을 운동 목록으로. 깨진 행은 빈 목록으로 읽는다 —
    템플릿 하나가 목록 전체를 못 열게 만들 이유가 없다."""
    try:
        rows = json.loads(raw or "[]")
    except json.JSONDecodeError:
        return []
    out: list[ProgramTemplateExercise] = []
    for row in rows if isinstance(rows, list) else []:
        if not isinstance(row, dict):
            continue
        try:
            out.append(ProgramTemplateExercise.model_validate(row))
        except ValueError:
            continue
    return out


def _dump(exercises: list[ProgramTemplateExercise]) -> str:
    return json.dumps(
        [item.model_dump() for item in exercises], ensure_ascii=False
    )


def _to_out(row: TrainerProgramTemplate) -> TrainerProgramTemplateOut:
    return TrainerProgramTemplateOut(
        id=row.id,
        name=row.name,
        goal=row.goal,
        exercises=_exercises(row.exercises_json),
        updated_at=row.updated_at,
    )


def starter_templates(locale: Locale | None = None) -> list[TrainerProgramTemplateOut]:
    """저장된 것이 없을 때 보여 주는 읽기 전용 시작 구성.

    [locale] 을 생략하면 요청 언어다(#2301).
    """
    starters = _STARTERS_EN if (locale or current_locale()) == "en" else _STARTERS
    stamp = datetime(2026, 1, 1, tzinfo=timezone.utc)
    return [
        TrainerProgramTemplateOut(
            id=f"{STARTER_PREFIX}{index}",
            name=name,
            goal=goal,
            exercises=[
                ProgramTemplateExercise(name=n, minutes=m, type=t)
                for n, m, t in items
            ],
            # 시작 구성에는 '언제 고쳤나' 가 없다. 목록 정렬만 흔들리지 않게
            # 고정값을 준다 — 매 요청 달라지면 화면이 이유 없이 다시 그려진다.
            updated_at=stamp,
        )
        for index, (name, goal, items) in enumerate(starters)
    ]


def list_templates(db: Session, trainer_id: str) -> list[TrainerProgramTemplateOut]:
    """내 템플릿(최근 수정 먼저). 하나도 없으면 시작 구성."""
    rows = db.scalars(
        select(TrainerProgramTemplate)
        .where(TrainerProgramTemplate.trainer_id == trainer_id)
        .order_by(
            TrainerProgramTemplate.updated_at.desc(),
            TrainerProgramTemplate.id.desc(),
        )
        .limit(TEMPLATE_LIMIT)
    ).all()
    if not rows:
        return starter_templates()
    return [_to_out(row) for row in rows]


def _owned(db: Session, trainer_id: str, template_id: str) -> TrainerProgramTemplate:
    row = db.scalar(
        select(TrainerProgramTemplate).where(
            TrainerProgramTemplate.id == template_id,
            TrainerProgramTemplate.trainer_id == trainer_id,
        )
    )
    if row is None:
        # 남의 템플릿도 여기로 온다 — 존재조차 드러내지 않는다.
        raise TemplateNotFound("템플릿을 찾을 수 없어요.")
    return row


def create_template(
    db: Session,
    trainer_id: str,
    *,
    name: str,
    goal: str,
    exercises: list[ProgramTemplateExercise],
) -> TrainerProgramTemplateOut:
    used = db.scalar(
        select(TrainerProgramTemplate.id)
        .where(TrainerProgramTemplate.trainer_id == trainer_id)
        .limit(TEMPLATE_LIMIT)
        .offset(TEMPLATE_LIMIT - 1)
    )
    if used is not None:
        raise TemplateLimitReached(
            f"템플릿은 최대 {TEMPLATE_LIMIT}개까지 저장할 수 있어요."
        )
    now = _now()
    row = TrainerProgramTemplate(
        id=f"tpl-{uuid.uuid4().hex[:12]}",
        trainer_id=trainer_id,
        name=name,
        goal=goal,
        exercises_json=_dump(exercises),
        created_at=now,
        updated_at=now,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return _to_out(row)


def update_template(
    db: Session, trainer_id: str, template_id: str, fields: dict
) -> TrainerProgramTemplateOut:
    row = _owned(db, trainer_id, template_id)
    for field in ("name", "goal"):
        if field in fields:
            setattr(row, field, fields[field])
    if "exercises" in fields:
        row.exercises_json = _dump(
            [
                item
                if isinstance(item, ProgramTemplateExercise)
                else ProgramTemplateExercise.model_validate(item)
                for item in fields["exercises"]
            ]
        )
    row.updated_at = _now()
    db.commit()
    db.refresh(row)
    return _to_out(row)


def delete_template(db: Session, trainer_id: str, template_id: str) -> None:
    """템플릿을 지운다. 이미 배정된 루틴은 건드리지 않는다 — 끼워 넣은 뒤로는
    서로 독립적인 데이터다."""
    row = _owned(db, trainer_id, template_id)
    db.delete(row)
    db.commit()
