"""담당 트레이너가 있는 회원의 AI 개인운동 후보를 준비한다. (#790)

승인 흐름(`trainer_service.approve_routine_suggestion`)만으로는 검토할 것이
생기지 않는다. 트레이너가 매번 회원을 골라 직접 생성을 요청해야 후보가 나오면
관리 부담이 줄지 않는다 — 이 이슈의 요구는 **AI 가 먼저 준비하고 트레이너는
판단만 한다**는 것이다. 이 모듈이 그 '먼저 준비' 를 맡는다.

세 가지를 의도적으로 좁혀 두었다.

1. **LLM 을 부르지 않는다.** 정규 프로그램 A/B 후보는 LLM 을
   쓰지만(`trainer_routine_options_service`), 그쪽은 트레이너가 버튼을 누르고
   기다리는 화면이다. 여기는 프로그램 탭을 열 때마다 지나는 조회 경로라, 왕복
   수 초에 분당 한도가 걸린 호출을 끼우면 탭이 그만큼 늦게 뜨고 한도가 차면
   목록이 비어 보인다. 개인운동은 `8분 어깨 스트레칭` 같은 짧은 단위여서 규칙과
   근거만으로도 판단 재료가 충분하다.
2. **회복 범위만 제안한다.** 고강도·고위험 운동을 기록만 보고 새로 처방하지
   않고, 질환을 근거로 치료 목적 운동을 만들지 않는다. 건강 정보는 강도를
   내리는 쪽으로만 읽는다. 트레이너 검토가 붙어도 이 경계는 유지한다 — 승인
   버튼이 있다는 것이 위험한 처방의 근거가 될 수는 없다
   (`auto_routine_service` 와 같은 원칙).
3. **트레이너 메모·PT 노트의 원문을 옮기지 않는다.** 메모가 있는지만 보고
   `최근 PT 피드백 반영` 같은 근거로 남긴다 — 트레이너는 자기가 쓴 메모가
   무엇인지 안다. 같은 칸(`TrainerSchedule.note`)에 PT 전 안내가 담길 수도
   있어(#2374) 사유 문장에서 메모를 "피드백" 이라고 단정하지 않는다.

신호가 하나도 없는 회원에게는 아무것도 만들지 않는다. 근거 없는 후보는
트레이너에게 판단할 재료를 주지 못하면서 검토 목록만 채운다.

**사유는 트레이너가 읽는 판단 재료다(#2579).** `reason` 은 "이 회원의 어떤
기록 때문에 이 운동이 올라왔나" 를 기록 숫자(최근 2주 운동 시간·근력 비중·PT
뒤 며칠)로 말한다. 회원에게 가지 않는다 — 회원 응답은 근거가 있는 행(= AI 제안)의
사유를 비우고(`trainer_service._routine_out`), 회원 카드에는 효과 한 줄
(`effect`, #2570)이 선다.

**언어(#2301).** 근거는 코드로 저장해 트레이너 웹이 화면 언어로 표시한다. 운동
이름과 `reason` 은 후보를 준비하는 요청(= 트레이너의 검토 목록 조회)의 언어로
만들어 저장한다.
"""
from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, field
from datetime import date, timedelta

from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.core.locale import Locale, current_locale, localized
from app.models.models import (
    ExerciseSession,
    HealthProfile,
    TrainerRoutine,
    TrainerSchedule,
)
from app.services import exercise_activity, exercise_types

#: 검토 대기 상태. 상수의 출처는 [app.services.trainer_service] 지만 그 모듈이 이
#: 모듈을 불러오므로 값을 여기서 다시 적는다(순환 import 회피) —
#: `auto_routine_service` 가 `approved` 를 다시 적는 것과 같은 이유다. 어긋나면
#: 검토 목록이 곧바로 비어서 드러난다.
ROUTINE_PENDING = "pending"

#: 신호를 찾는 기간. 넓히면 이미 나은 통증이나 지난달 운동 편중이 계속 후보를
#: 만들고, 좁히면 주 1~2회 오는 회원의 PT 가 기간 밖으로 밀린다.
LOOKBACK_DAYS = 14

#: `PT 직후` 로 볼 기간. 회복 목적 운동은 수업과 붙어 있어야 의미가 있다.
RECENT_PT_DAYS = 3

#: 근력 편중으로 볼 비율. 최근 운동 시간의 절반을 넘으면 회복 쪽을 제안한다.
STRENGTH_HEAVY_RATIO = 0.5

#: 한 번에 준비하는 후보 수 상한. 개인운동은 PT 사이를 메우는 것이지 할 일
#: 목록이 아니다.
MAX_NEW_SUGGESTIONS = 2

#: 검토 대기가 이만큼 쌓이면 더 만들지 않는다. 트레이너가 며칠 들여다보지
#: 않았을 때 밀린 후보가 계속 늘면, 돌아왔을 때 검토를 시작할 마음이 들지 않는
#: 목록이 된다.
MAX_PENDING_BACKLOG = 4

#: 근거 **코드**. 문장이 아니라 코드로 저장하고 보낸다 — 트레이너 웹이 화면
#: 언어에 맞는 문구(ARB)로 바꿔 보여 준다(#2301). 문장으로 저장하면 한 번 만든
#: 후보의 근거가 영어 화면에서도 영영 한국어로 남는다. 스키마
#: (`RoutineSuggestionCreateRequest.evidence`)의 길이 상한 안에 든다.
EV_RECENT_PT = "recent_pt_feedback"
EV_STRENGTH_HEAVY = "strength_heavy"
EV_BLOOD_PRESSURE = "blood_pressure_goal"
EV_LOW_CARDIO = "low_cardio"
EV_RECENT_RECORD = "recent_record"

#: 서버가 만드는 근거 코드 전부. 앱은 이 밖의 값을 받으면 원문 그대로 보여 준다.
EVIDENCE_CODES: tuple[str, ...] = (
    EV_RECENT_PT,
    EV_STRENGTH_HEAVY,
    EV_BLOOD_PRESSURE,
    EV_LOW_CARDIO,
    EV_RECENT_RECORD,
)

#: 코드로 바꾸기 전(#2301)에 문장으로 저장된 근거 → 코드. 이미 준비된 검토 대기
#: 후보가 영어 화면에서도 번역되게, 읽는 쪽(`trainer_service.suggestion_evidence`)이
#: 이 표로 코드로 되돌린다. 모르는 문장은 원문 그대로 둔다.
LEGACY_EVIDENCE_LABELS: dict[str, str] = {
    "최근 PT 피드백 반영": EV_RECENT_PT,
    "최근 근력운동 비중 높음": EV_STRENGTH_HEAVY,
    "혈압 관리 목표": EV_BLOOD_PRESSURE,
    "최근 유산소 비중 낮음": EV_LOW_CARDIO,
    "최근 운동 기록 반영": EV_RECENT_RECORD,
}

#: 혈압 관리로 읽을 질환 표기. 회원이 적는 표기가 일정하지 않아 부분 문자열로
#: 본다. 이 신호는 **강도를 내리는 쪽으로만** 쓴다.
_BLOOD_PRESSURE_TERMS = ("고혈압", "혈압")

#: 집계는 표준 어휘로 접어서 한다 (#996) — 옛 값(walking·걷기)도 같은 칸에
#: 떨어지므로 종류를 나열해 두지 않는다.
_STRENGTH_TYPES = (exercise_types.STRENGTH,)
_CARDIO_TYPES = (exercise_types.CARDIO,)


@dataclass(frozen=True)
class _Signals:
    """후보를 만들 근거. 하나도 없으면 후보를 만들지 않는다."""

    #: 최근 완료된 PT 가 [RECENT_PT_DAYS] 안에 있다.
    pt_just_finished: bool = False
    #: 최근 PT 노트나 배정 루틴 피드백이 남아 있다.
    trainer_feedback: bool = False
    #: 최근 운동 시간이 근력에 몰려 있다.
    strength_heavy: bool = False
    #: 최근 유산소 기록이 없다(운동 기록 자체는 있다).
    low_cardio: bool = False
    #: 혈압 관리가 필요한 회원이다.
    blood_pressure: bool = False
    #: 기간 안에 운동 기록이 하나라도 있다.
    has_records: bool = False
    #: 기간 안 운동 시간 합계와 그중 근력 시간(분). 사유 문장이 이 숫자로
    #: 근력 편중을 말한다(#2579).
    total_minutes: int = 0
    strength_minutes: int = 0
    #: 가장 최근 완료 PT 가 며칠 전인가. 기간 안에 없으면 None.
    days_since_pt: int | None = None

    @property
    def empty(self) -> bool:
        return not (
            self.pt_just_finished
            or self.trainer_feedback
            or self.strength_heavy
            or self.low_cardio
            or self.blood_pressure
            or self.has_records
        )


@dataclass(frozen=True)
class _Candidate:
    """준비할 후보 하나. 사유 문장(`reason`)과 근거 코드(`evidence`)는 둘 다
    트레이너가 읽는 판단 재료다(#2579)."""

    name: str
    minutes: int
    type: str
    reason: str
    evidence: tuple[str, ...] = field(default=())


def _key_for(day: date) -> str:
    """그날 준비한 후보 묶음을 가리키는 키.

    배정 멱등키(`client_request_id`)와 같은 컬럼을 쓴다. 유니크 제약이
    `(trainer_id, member_id, client_request_id)` 라, 같은 날 프로그램 탭을 몇 번
    열어도 후보가 늘지 않는다 — 트레이너가 하나를 승인하고 하나를 거절한 뒤
    새로고침해도 그날 후보가 다시 생기지 않는다.
    """
    return f"sug-{day.isoformat()}"


def ensure_suggestions(db: Session, trainer_id: str, member_id: str) -> None:
    """이 회원의 오늘 후보를 준비한다. 이미 있으면 아무것도 하지 않는다.

    부르는 쪽은 트레이너의 검토 목록 조회다. 스케줄러 없이 "트레이너가 프로그램
    탭을 열면 준비돼 있다" 를 만족시키는 가장 단순한 방법이고, 회원 조회가
    자동 추천을 준비하는 방식(`auto_routine_service`)과 같은 자리다.

    **승인 전이므로 알림을 보내지 않는다.** 회원은 물론 트레이너에게도 보내지
    않는다 — 트레이너는 지금 이 화면을 열어 목록을 보고 있다.
    """
    key = _key_for(clock.today())
    if _prepared_today(db, trainer_id, member_id, key):
        return
    if _pending_count(db, trainer_id, member_id) >= MAX_PENDING_BACKLOG:
        return

    signals = _collect_signals(db, trainer_id, member_id)
    candidates = _candidates_for(signals, current_locale())
    if not candidates:
        return

    max_order = db.scalar(
        select(func.max(TrainerRoutine.sort_order)).where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
        )
    )
    now = clock.now()
    for offset, candidate in enumerate(candidates[:MAX_NEW_SUGGESTIONS]):
        db.add(
            TrainerRoutine(
                id=f"sug-{uuid.uuid4().hex[:12]}",
                trainer_id=trainer_id,
                member_id=member_id,
                name=candidate.name,
                minutes=candidate.minutes,
                type=candidate.type,
                reason=candidate.reason,
                source="ai",
                status=ROUTINE_PENDING,
                sort_order=(max_order or 0) + 1 + offset,
                evidence_json=json.dumps(
                    list(candidate.evidence), ensure_ascii=False
                ),
                # 묶음 전체가 한 키를 쓴다. 후보 하나만 들어가고 나머지가 빠지는
                # 상태가 없어야 트레이너가 보는 목록이 매번 같다.
                client_request_id=key if offset == 0 else f"{key}-{offset}",
                created_at=now,
            )
        )
    try:
        db.commit()
    except IntegrityError:
        # 트레이너가 두 창에서 같은 회원을 동시에 열면 두 요청이 같은 키로
        # 들어온다. 먼저 커밋한 쪽의 후보가 남으면 되므로 조용히 넘긴다.
        db.rollback()


def _prepared_today(
    db: Session, trainer_id: str, member_id: str, key: str
) -> bool:
    """그날 후보를 이미 준비했나. 승인·거절한 것도 '준비했다'로 본다."""
    return (
        db.scalar(
            select(TrainerRoutine.id)
            .where(
                TrainerRoutine.trainer_id == trainer_id,
                TrainerRoutine.member_id == member_id,
                TrainerRoutine.client_request_id.like(f"{key}%"),
            )
            .limit(1)
        )
        is not None
    )


def _pending_count(db: Session, trainer_id: str, member_id: str) -> int:
    return (
        db.scalar(
            select(func.count(TrainerRoutine.id)).where(
                TrainerRoutine.trainer_id == trainer_id,
                TrainerRoutine.member_id == member_id,
                TrainerRoutine.status == ROUTINE_PENDING,
            )
        )
        or 0
    )


def _collect_signals(
    db: Session, trainer_id: str, member_id: str
) -> _Signals:
    """회원의 최근 기록에서 후보의 근거가 될 신호를 모은다."""
    today = clock.today()
    # 최근 구간은 **오늘을 포함한 [LOOKBACK_DAYS] 개 날짜**다. PT·운동·피드백이
    # 모두 같은 구간을 보아야 "최근" 이 신호마다 다른 뜻이 되지 않는다.
    since, _ = exercise_activity.recent_window(LOOKBACK_DAYS, today=today)
    window = (since, today)

    # 완료된 PT 는 날짜(문자열 YYYY-MM-DD)로 비교한다 — 컬럼이 그 표기라
    # 사전순 비교가 곧 날짜 비교다(다른 조회들도 같은 방식이다).
    pt_rows = db.execute(
        select(TrainerSchedule.date, TrainerSchedule.note).where(
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.member_id == member_id,
            TrainerSchedule.status == "완료",
            TrainerSchedule.date >= since.isoformat(),
            # 상담은 PT 가 아니다 — 상담 일정의 글은 상담 메모라 PT 피드백으로
            # 세지 않고, 상담을 마친 것을 "방금 PT 를 마쳤다" 로 읽지도 않는다(#2587).
            TrainerSchedule.type != "상담",
        )
    ).all()

    recent_cutoff = (today - timedelta(days=RECENT_PT_DAYS)).isoformat()
    pt_just_finished = any(row.date >= recent_cutoff for row in pt_rows)
    latest_pt = max((row.date for row in pt_rows), default=None)
    days_since_pt = (
        (today - date.fromisoformat(latest_pt)).days if latest_pt else None
    )
    pt_note = any((row.note or "").strip() for row in pt_rows)

    # 운동 기록은 **논리 운동일**(고객 앱이 보는 날짜)로 거른다 (#1264).
    # `created_at` 은 적재 시각이라, 재시드한 35주 전 운동도 방금 만든 행이
    # 되어 최근 운동으로 오인된다.
    recent_sessions = [
        row
        for row in db.scalars(_recent_sessions_query(member_id, window)).all()
        if exercise_activity.in_window(
            exercise_activity.activity_date_of(row), window
        )
    ]

    routine_feedback = any(
        row.assigned_trainer_id == trainer_id
        and (row.trainer_feedback or "").strip()
        for row in recent_sessions
    )

    minutes_by_type: dict[str, int] = {}
    for row in recent_sessions:
        minutes_by_type[row.type] = minutes_by_type.get(row.type, 0) + int(
            row.minutes or 0
        )
    total_minutes = sum(minutes_by_type.values())
    strength_minutes = sum(
        minutes
        for t, minutes in minutes_by_type.items()
        if exercise_types.normalize(t) in _STRENGTH_TYPES
    )
    cardio_minutes = sum(
        minutes
        for t, minutes in minutes_by_type.items()
        if exercise_types.normalize(t) in _CARDIO_TYPES
    )

    conditions = db.scalar(
        select(HealthProfile.conditions).where(
            HealthProfile.user_id == member_id
        )
    )
    blood_pressure = any(
        term in (conditions or "") for term in _BLOOD_PRESSURE_TERMS
    )

    return _Signals(
        pt_just_finished=pt_just_finished,
        trainer_feedback=pt_note or routine_feedback,
        strength_heavy=(
            total_minutes > 0
            and strength_minutes / total_minutes > STRENGTH_HEAVY_RATIO
        ),
        low_cardio=total_minutes > 0 and cardio_minutes == 0,
        blood_pressure=blood_pressure,
        has_records=total_minutes > 0 or bool(pt_rows),
        total_minutes=total_minutes,
        strength_minutes=strength_minutes,
        days_since_pt=days_since_pt,
    )


def _recent_sessions_query(member_id: str, window: tuple[date, date]):
    """구간에 닿을 수 있는 운동 기록만 가져오는 조회.

    세 갈래로 넓게 긁고 최종 판정은 파이썬이 [exercise_activity.activity_date_of]
    로 한다 — 주차만 걸면 `week_start` 가 깨진 옛 행을 놓치고, 반대로 전체를
    읽으면 35주치 데모에서 245일이 매번 끌려온다.
    """
    start, _ = window
    since_ts = exercise_activity.start_of_day(start)
    return select(ExerciseSession).where(
        ExerciseSession.user_id == member_id,
        or_(
            ExerciseSession.week_start.in_(
                exercise_activity.week_starts_covering(*window)
            ),
            ExerciseSession.completed_at >= since_ts,
            ExerciseSession.created_at >= since_ts,
        ),
    )


def _candidates_for(
    signals: _Signals, locale: Locale = "ko"
) -> list[_Candidate]:
    """신호를 회복 범위의 후보로 옮긴다. 신호가 없으면 빈 목록.

    순서가 곧 우선순위다 — 상한([MAX_NEW_SUGGESTIONS])에 걸리면 뒤가 잘린다.
    회복(PT 직후·근력 편중)을 먼저 두는 이유는 그쪽이 다음 수업까지의 컨디션에
    직접 닿기 때문이다.

    이름·`reason` 은 [locale] 로 쓴다(#2301). 근거는 언어와 무관한 코드다.
    `reason` 은 트레이너가 읽는 문장이라 신호를 기록 숫자로 말하고, 무엇을
    하기 좋은지로 맺는다(#2579).
    """
    if signals.empty:
        return []

    out: list[_Candidate] = []

    if signals.pt_just_finished or signals.strength_heavy:
        evidence: list[str] = []
        if signals.pt_just_finished and signals.trainer_feedback:
            evidence.append(EV_RECENT_PT)
        if signals.strength_heavy:
            evidence.append(EV_STRENGTH_HEAVY)
        if not evidence:
            evidence.append(EV_RECENT_RECORD)
        out.append(
            _Candidate(
                name=localized(
                    "하체·전신 회복 스트레칭",
                    "Lower & full-body recovery stretch",
                    locale,
                ),
                minutes=10,
                type="스트레칭",
                reason=_recovery_reason(signals, locale),
                evidence=tuple(evidence),
            )
        )

    if signals.blood_pressure or signals.low_cardio:
        evidence = []
        if signals.blood_pressure:
            evidence.append(EV_BLOOD_PRESSURE)
        if signals.low_cardio:
            evidence.append(EV_LOW_CARDIO)
        out.append(
            _Candidate(
                name=localized("저강도 걷기", "Low-intensity walk", locale),
                minutes=20,
                type="유산소",
                reason=_walk_reason(signals, locale),
                evidence=tuple(evidence),
            )
        )

    if not out:
        # 기록은 있지만 편중·질환 신호가 없는 회원. 굳이 새 운동을 처방하지
        # 않고, 다음 수업을 준비하는 범위에서 가장 가벼운 것 하나만 둔다.
        out.append(
            _Candidate(
                name=localized(
                    "목·어깨 스트레칭", "Neck & shoulder stretch", locale
                ),
                minutes=8,
                type="스트레칭",
                reason=localized(
                    "최근 2주 기록에 치우침이나 건강 신호가 없어요. "
                    "다음 수업 준비용으로 가장 가벼운 스트레칭만 두었어요.",
                    "No imbalance or health flags in the last 2 weeks. "
                    "Only the lightest stretch is suggested, to prepare for "
                    "the next session.",
                    locale,
                ),
                evidence=(
                    EV_RECENT_PT if signals.trainer_feedback else EV_RECENT_RECORD,
                ),
            )
        )
    return out


def _pt_days_ago(days: int, locale: Locale) -> str:
    """최근 PT 가 며칠 전이었나 — 오늘이면 `오늘`."""
    if days <= 0:
        return localized("오늘 PT 가 있었어요.", "There was a PT session today.", locale)
    return localized(
        f"{days}일 전 PT 가 있었어요.",
        f"There was a PT session {days} day{'s' if days != 1 else ''} ago.",
        locale,
    )


def _recovery_reason(signals: _Signals, locale: Locale) -> str:
    """회복 스트레칭의 사유 — 근력 비중·PT 뒤 며칠을 숫자로. (#2579)"""
    parts: list[str] = []
    if signals.strength_heavy and signals.total_minutes > 0:
        share = round(signals.strength_minutes * 100 / signals.total_minutes)
        parts.append(
            localized(
                f"최근 2주 운동 {signals.total_minutes}분 중 "
                f"{signals.strength_minutes}분({share}%)이 근력이에요.",
                f"In the last 2 weeks, {signals.strength_minutes} of "
                f"{signals.total_minutes} min ({share}%) was strength training.",
                locale,
            )
        )
    if signals.pt_just_finished and signals.days_since_pt is not None:
        parts.append(_pt_days_ago(signals.days_since_pt, locale))
    parts.append(
        localized(
            "다음 수업 전까지 회복 스트레칭으로 풀어 두기 좋아요.",
            "A recovery stretch helps loosen up before the next session.",
            locale,
        )
    )
    return " ".join(parts)


def _walk_reason(signals: _Signals, locale: Locale) -> str:
    """저강도 걷기의 사유 — 혈압 목표·유산소 기록 없음. (#2579)"""
    if signals.blood_pressure and signals.low_cardio:
        head = localized(
            "혈압 관리가 목표인데 최근 2주 유산소 기록이 없어요.",
            "Blood pressure is a goal, but there is no cardio in the last 2 weeks.",
            locale,
        )
    elif signals.blood_pressure:
        head = localized(
            "혈압 관리가 목표예요.", "Blood pressure is one of the goals.", locale
        )
    else:
        head = localized(
            f"최근 2주 운동 {signals.total_minutes}분 중 유산소가 없어요.",
            f"None of the {signals.total_minutes} min in the last 2 weeks "
            "was cardio.",
            locale,
        )
    return " ".join(
        (
            head,
            localized(
                "대화할 수 있는 속도의 걷기부터 시작하기 좋아요.",
                "Start with walking at a conversational pace.",
                locale,
            ),
        )
    )
