"""담당 트레이너가 없는 회원에게 주는 안전 범위 개인운동. (#782)

담당 트레이너가 있으면 AI 후보는 트레이너 검토를 거쳐 회원에게 간다(#790).
승인할 사람이 없는 회원에게는 그 단계가 없으므로, **추천 자체를 보수적으로**
가져간다.

무엇을 추천하지 않는가가 이 모듈의 핵심이다.

- 고강도·고위험 운동을 회원 기록만으로 새로 처방하지 않는다.
- 질환을 근거로 치료 목적 운동을 처방하지 않는다.
- 건강 정보를 읽어 강도를 올리지 않는다 — 읽더라도 내리는 쪽으로만 쓴다.

남는 것은 걷기·스트레칭 같은 회복 범위다. 트레이너가 붙는 순간 이 경로는 멈추고
검토 흐름으로 넘어간다.
"""
from __future__ import annotations

import uuid
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import ExerciseSession, TrainerRoutine
from app.services.coach import insights

#: 검토 상태 상수는 [app.services.trainer_service] 가 갖고 있지만, 그 모듈이 이
#: 모듈을 import 하므로 값을 여기서 다시 적는다(순환 import 회피). 문자열 하나라
#: 어긋날 여지가 작고, 어긋나면 회원 조회에서 곧바로 빈 목록으로 드러난다.
ROUTINE_APPROVED = "approved"

#: 하루에 준비하는 추천. 개수를 묶어 두는 이유는 "할 일 목록" 이 되지 않게
#: 하려는 것이다 — PT 사이를 메우는 운동이지 프로그램이 아니다.
SAFE_ROUTINES: tuple[tuple[str, int, str, str], ...] = (
    (
        "저강도 걷기",
        20,
        "유산소",
        "회복 목적의 가벼운 유산소예요. 대화할 수 있는 속도로 걸어 보세요.",
    ),
    (
        "전신 스트레칭",
        10,
        "스트레칭",
        "굳은 근육을 풀어 다음 운동을 준비해요. 통증이 있으면 멈추세요.",
    ),
)


#: 체중을 싣는 종목. 하지·허리가 불편하면 그만큼 부담이 간다.
_WEIGHT_BEARING: frozenset[str] = frozenset({"저강도 걷기"})

#: 체중을 싣는 종목을 권하지 않을 부위. 회원이 쓴 말 그대로 잡히므로
#: (`coach/insights.py`) 한국어·영어를 함께 둔다.
_LOAD_SENSITIVE_PARTS: frozenset[str] = frozenset(
    {"무릎", "발목", "허리", "Knee", "Ankle", "Back"}
)

#: 시간을 줄일 때의 하한. 이보다 짧으면 권하는 뜻이 없다.
_MIN_MINUTES = 5


def _adjust_for_insights(db: Session, member_id: str) -> list[tuple[str, int, str, str]]:
    """최근 대화에서 찾은 불편을 반영해 오늘의 추천을 좁힌다. (#2016)

    **내리는 쪽으로만 쓴다.** 이 모듈의 원칙 그대로다 — 건강 정보를 읽어 강도를
    올리지 않는다. 여기서 하는 일은 둘뿐이다.

    - 체중을 싣는 종목은 하지·허리가 불편할 때 빼 버린다. 대신 다른 운동을
      끼워 넣지 않는다 — 그것은 처방이다.
    - 운동이 힘들다고 말한 적이 있으면 남은 종목의 **시간을 줄인다**.

    회원이 기록 창에서 치운 감지는 `recent_insights` 가 이미 건너뛴다(#1975).

    남는 것이 없으면 빈 목록이다. 불편한 곳이 여럿이면 함부로 권하지 않는 편이
    맞다 — 승인할 트레이너가 없는 경로라 더 그렇다.
    """
    records = insights.recent_insights(db, member_id)
    if not records:
        return list(SAFE_ROUTINES)

    sore_parts = {
        r.body_part
        for r in records
        if r.kind == insights.KIND_DISCOMFORT and r.body_part
    }
    avoid_weight_bearing = bool(sore_parts & _LOAD_SENSITIVE_PARTS)
    struggled = any(r.kind == insights.KIND_NEGATIVE for r in records)

    adjusted: list[tuple[str, int, str, str]] = []
    for name, minutes, type_, reason in SAFE_ROUTINES:
        if avoid_weight_bearing and name in _WEIGHT_BEARING:
            continue
        if struggled:
            # 진단하거나 원인을 단정하지 않는다 — 줄였다는 사실만 말한다.
            minutes = max(_MIN_MINUTES, minutes // 2)
            reason = f"{reason} 오늘은 짧게 가도 괜찮아요."
        adjusted.append((name, minutes, type_, reason))
    return adjusted


def _key_for(day: date) -> str:
    """그날의 추천 묶음을 가리키는 키. 같은 날 여러 번 불려도 한 번만 만든다."""
    return f"auto-{day.isoformat()}"


def _existing_for(
    db: Session, member_id: str, key: str
) -> list[TrainerRoutine]:
    """그날 이미 만들어 둔 자동 추천.

    유니크 제약(`trainer_id`, `member_id`, `client_request_id`)에 기대지 않는다 —
    `trainer_id` 가 NULL 이면 Postgres 는 그 행들을 서로 다른 것으로 보아 제약이
    걸리지 않는다. 그래서 여기서 직접 확인한다.
    """
    return list(
        db.scalars(
            select(TrainerRoutine).where(
                TrainerRoutine.member_id == member_id,
                TrainerRoutine.trainer_id.is_(None),
                TrainerRoutine.client_request_id == key,
            )
        ).all()
    )


def ensure_auto_routines(db: Session, member_id: str) -> None:
    """담당 트레이너가 없는 회원의 오늘 추천을 준비한다.

    부르는 쪽은 회원의 루틴 조회다. 스케줄러 없이 "회원이 볼 때 준비돼 있다" 를
    만족시키는 가장 단순한 방법이고, 같은 날 여러 번 열어도 목록이 늘지 않는다.

    이미 만든 날에도 **대화에서 찾은 불편이 바뀌었으면 고친다**(#2016). 한 번
    만들고 끝내면, 아침에 화면을 연 회원이 점심에 "무릎이 아파요" 라고 말해도
    그날 하루 걷기가 그대로 권해진다. 기록 창에서 오탐을 치웠을 때도 같다 —
    치운 것이 다음 날에야 반영된다. 끝낸 운동은 건드리지 않는다: 이미 한 운동이
    목록에서 사라지면 회원이 한 일이 지워진 것처럼 보인다.

    알림을 보내지 않는다 — 회원이 직접 열어 본 화면에서 이미 보고 있다.
    """
    today = clock.now().date()
    key = _key_for(today)
    # 대화에서 찾은 불편을 반영해 좁힌다(#2016).
    todays = _adjust_for_insights(db, member_id)
    existing = _existing_for(db, member_id, key)
    # 회원이 오늘 지운 추천은 목록에서 내려와 있다(#2161). 다시 만들지 않는다 —
    # 고쳐 만들 때마다 지운 것이 되살아나면 회원은 지울 수 없는 목록을 보게 된다.
    removed_names = {
        r.name for r in existing
        if r.ended_on is not None and r.ended_on <= today.isoformat()
    }
    existing = [r for r in existing if r.name not in removed_names]
    todays = [t for t in todays if t[0] not in removed_names]

    done_ids = (
        set(
            db.scalars(
                select(ExerciseSession.assigned_routine_id).where(
                    ExerciseSession.assigned_routine_id.in_([r.id for r in existing])
                )
            ).all()
        )
        if existing
        else set()
    )
    done = [r for r in existing if r.id in done_ids]
    pending = sorted(
        (r for r in existing if r.id not in done_ids), key=lambda r: r.sort_order
    )
    done_names = {r.name for r in done}
    wanted = [t for t in todays if t[0] not in done_names]

    # 바뀐 것이 없으면 그대로 둔다 — 같은 날 다시 열었을 때 id 가 바뀌지 않는다.
    if [(r.name, r.minutes, r.reason) for r in pending] == [
        (name, minutes, reason) for name, minutes, _, reason in wanted
    ]:
        return

    for row in pending:
        db.delete(row)
    now = clock.now()
    start = max((r.sort_order for r in done), default=-1) + 1
    for order, (name, minutes, type_, reason) in enumerate(wanted, start=start):
        db.add(
            TrainerRoutine(
                id=f"auto-{uuid.uuid4().hex[:12]}",
                trainer_id=None,
                member_id=member_id,
                name=name,
                minutes=minutes,
                type=type_,
                reason=reason,
                source="ai",
                # 승인할 사람이 없으므로 바로 보이는 상태로 만든다. 보수적인
                # 범위로 좁힌 것이 여기서의 안전장치다.
                status=ROUTINE_APPROVED,
                sort_order=order,
                client_request_id=key,
                # 하루치 추천이다 — 오늘만 걸리고 내일은 그날 추천으로 바뀐다
                # (#2161). 지난 날짜 화면은 이 창으로 그날 목록을 되살린다.
                active_from=today.isoformat(),
                ended_on=(today + timedelta(days=1)).isoformat(),
                created_at=now,
            )
        )
    db.commit()
