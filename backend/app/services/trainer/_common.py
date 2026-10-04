"""트레이너 도메인 공용 도우미 — 날짜·라벨·기록 표기, 루틴·일정 상태 어휘, 여러 영역이 함께 쓰는 집계·변환.

영역 모듈끼리 서로의 비공개 헬퍼를 직접 부르지 않고 이 모듈을 거친다(#2909).
"""
from __future__ import annotations

import json
import re
import uuid
from collections import defaultdict
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Any

from sqlalchemy import func, or_, select, update
from sqlalchemy.orm import Session, object_session
from pydantic import ValidationError

from app.core import clock
from app.core.locale import current_locale, localized
from app.models.models import (
    ChatMessage, ConsultationRequest, DietEntry, ExerciseSession, HealthProfile,
    TrainerClient, TrainerReservation, TrainerRoutine, TrainerSchedule,
)
from app.schemas.trainer_api import (
    ProgramDraftExercise,
    ProgramDraftSession,
    ProgramItem, RoutineHistoryExerciseOut,
    RoutineHistoryKind,
    RoutineHistoryOut,
    RoutineOut, ScheduleConsultationOut, ScheduleSessionOut, WeeklyReportDayOut,
)
from app.data import routine_effects
from app.services import (
    data_consent_service,
    exercise_activity,
    exercise_service,
    exercise_types,
    goal_defaults,
    notification_service,
    notification_templates,
    routine_suggestion_service,
)
from app.services.exercise_duration import format_duration, seconds_or_minutes


# 일일 나트륨 목표(mg). 프론트 `sodiumTargetMg` 와 같은 값 — 리포트의
# '초과 N일'이 앱 화면의 경고와 어긋나면 안 된다. 원본은 `goal_defaults`(#2906).
SODIUM_TARGET_MG = goal_defaults.DAILY_SODIUM_MG


class IdempotencyConflict(Exception):
    """같은 멱등키가 이미 다른 payload 에 사용됐다."""


def _today() -> date:
    return clock.today()


def today_iso() -> str:
    """오늘 날짜 YYYY-MM-DD (라우터 기본 날짜용)."""
    return _today().isoformat()


def _meal_kr(meal_type: str) -> str:
    """끼니 종류 → 트레이너 웹이 그리는 한국어 라벨.

    키는 회원 앱 `MealType.name` 이다(#1988 의 `lateNight` 포함). 모르는 값은
    접지 않고 그대로 돌려준다 — 간식으로 접으면 새 끼니가 조용히 낮의 간식과
    한 칸에 섞인다.
    """
    return {
        "breakfast": "아침",
        "lunch": "점심",
        "dinner": "저녁",
        "snack": "간식",
        "lateNight": "야식",
    }.get(meal_type, meal_type)


def relative_day_label(day: str) -> str:
    """YYYY-MM-DD → 오늘/어제/N일 전 (마지막 루틴 전송 라벨용).

    화면 언어를 따르는 앱은 이 문장 대신 원래 날짜(`last_routine_date`)를 받아
    직접 그린다(#2300). 이 라벨은 그 필드를 모르는 옛 앱을 위해 남았고, 요청
    언어가 영어면 영어로 만든다 — 헤더가 없으면 지금까지와 같은 한국어다.
    """
    try:
        then = date.fromisoformat(day)
    except ValueError:
        return day
    delta = (_today() - then).days
    if delta <= 0:
        return localized("오늘", "Today")
    if delta == 1:
        return localized("어제", "Yesterday")
    return localized(f"{delta}일 전", f"{delta} days ago")


def history_date_label(day: str) -> str:
    """YYYY-MM-DD → 'M/D' (+ ' (오늘)'/' (어제)') 운동기록 라벨.

    [relative_day_label] 과 같은 이유로 앱은 `date` 필드를 쓰고(#2300), 이 라벨은
    옛 앱을 위한 것이다.
    """
    try:
        then = date.fromisoformat(day)
    except ValueError:
        return day
    label = f"{then.month}/{then.day}"
    delta = (_today() - then).days
    if delta == 0:
        label += localized(" (오늘)", " (Today)")
    elif delta == 1:
        label += localized(" (어제)", " (Yesterday)")
    return label


def _iso_day_or_none(day: str | None) -> str | None:
    """`YYYY-MM-DD` 로 읽히는 값만 그대로, 아니면 None.

    이력의 날짜 칸은 문자열이라 깨진 값이 들어 있을 수 있다. 그 값을 날짜라고
    내려보내면 앱이 엉뚱한 날로 읽으므로, 모르는 날은 모른다고 보낸다 — 그때 앱은
    `date_label` 을 그대로 쓴다.
    """
    if not day:
        return None
    try:
        return date.fromisoformat(day).isoformat()
    except ValueError:
        return None


#: 완료한 PT 세션이 운동 이력에 남기는 이름. **DB 에 그대로 저장되는 값**이라
#: 번역하지 않는다 — 화면은 [history_kind_code] 가 준 코드로 그린다(#2300).
PT_HISTORY_KIND_LABEL = "PT 세션 · 트레이너 지도"

#: 이름 없이 배정된 루틴을 수행한 이력의 이름. 저장하지 않고 응답 때 붙인다.
ASSIGNED_HISTORY_FALLBACK_LABEL = "배정 루틴 수행"
#: 하루치 개인운동 완료 카드의 이름(#2510). 트레이너 웹은 `kind` 로 번역한다.
PERSONAL_HISTORY_LABEL = "개인운동"

#: 서버가 붙이는 고정 이름 → 이력 종류 코드. 트레이너가 지은 이름처럼 여기 없는
#: 이름은 코드가 없다(사람이 쓴 말은 번역 대상이 아니다).
_HISTORY_KIND_CODES: dict[str, RoutineHistoryKind] = {
    PT_HISTORY_KIND_LABEL: "pt_session",
    "AI 개인운동": "ai_personal",
    # 옛 시드·픽스처의 이름. 지금은 `AI 개인운동` 으로 부른다(#1453).
    "AI 루틴 · 자율 운동": "ai_personal",
    ASSIGNED_HISTORY_FALLBACK_LABEL: "assigned_routine",
    PERSONAL_HISTORY_LABEL: "personal_routine",
}


def history_kind_code(label: str | None) -> RoutineHistoryKind | None:
    """이력 이름이 서버가 붙인 고정 이름이면 그 종류 코드, 아니면 None."""
    if not label:
        return None
    return _HISTORY_KIND_CODES.get(label.strip())


#: 이력 한 줄 끝에 붙는 양. `3세트`·`12회`·`60초`·`40kg`·`25분` 이 공백이나 `·` 로
#: 이어진다. [_program_item_label] 과 시드가 만드는 모양이다.
_HISTORY_AMOUNT_TAIL_RE = re.compile(
    r"(?:(?:\s*·\s*|\s+)\d+(?:\.\d+)?(?:세트|회|초|kg|분))+\s*$"
)


_HISTORY_AMOUNT_RE = re.compile(r"(\d+(?:\.\d+)?)(세트|회|초|kg|분)")


_HISTORY_MARK_RE = re.compile(r"\s*[✓✗]\s*")


def parse_history_exercise(raw: object) -> RoutineHistoryExerciseOut:
    """저장된 이력 한 줄 → 값으로 나눈 운동 한 종목(#2300).

    `RoutineHistory.exercises_json` 은 `스쿼트 3세트 12회 40kg` 이나
    `스쿼트 3세트 · 12회 · 40kg ✓` 같은 **한국어 문장**으로 저장돼 있다(완료한 PT
    세션·시드). 이미 쌓인 행을 고치는 대신 읽을 때 값으로 되돌린다 — 단위가
    이름 **끝에** 이어 붙은 모양만 값으로 읽고, 그 밖의 줄은 적힌 그대로 이름으로
    둔다(`플랭크 ✗ (피로)` → 이름 `플랭크 (피로)`, 한 적 없음).

    완료한 PT 세션은 이제 값을 객체로 저장한다([_program_history_entry], #2546) —
    문장의 `초` 는 버티는 운동의 초로 되읽혀, 운동 시간 `45초` 를 문장으로는 남길
    수 없었다. 문장은 그 뒤로도 옛 행에서만 읽는다.
    """
    if isinstance(raw, dict):
        return _history_exercise_from_dict(raw)
    text = str(raw or "")
    done = "✗" not in text
    body = " ".join(_HISTORY_MARK_RE.sub(" ", text).split())
    tail = _HISTORY_AMOUNT_TAIL_RE.search(body)
    name = body[: tail.start()].strip().rstrip("·").strip() if tail else body
    if tail is None or not name:
        return RoutineHistoryExerciseOut(name=body, done=done)
    amounts: dict[str, str] = {}
    for value, unit in _HISTORY_AMOUNT_RE.findall(tail.group(0)):
        # 같은 단위가 두 번 적힌 줄은 없다 — 있으면 처음 것을 믿는다.
        amounts.setdefault(unit, value)

    def _int(unit: str) -> int | None:
        value = amounts.get(unit)
        return int(float(value)) if value is not None else None

    weight = amounts.get("kg")
    strength = any(unit in amounts for unit in ("세트", "회", "초", "kg"))
    return RoutineHistoryExerciseOut(
        name=name,
        type=exercise_types.STRENGTH if strength else "",
        minutes=_int("분") or 0,
        sets=_int("세트"),
        reps=_int("회"),
        hold_seconds=_int("초"),
        weight=float(weight) if weight is not None else None,
        done=done,
    )


def _history_exercise_from_dict(raw: dict) -> RoutineHistoryExerciseOut:
    """값까지 실린 이력 항목(객체) → 같은 모양. 깨진 칸은 비운다."""

    def _num(key: str, cast: Callable[[Any], Any]) -> Any:
        value = raw.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return None
        return cast(value)

    type_ = raw.get("type")
    intensity = raw.get("intensity")
    return RoutineHistoryExerciseOut(
        name=str(raw.get("name") or ""),
        type=exercise_types.normalize(type_) if type_ else "",
        minutes=_num("minutes", int) or 0,
        sets=_num("sets", int),
        reps=_num("reps", int),
        hold_seconds=_num("hold_seconds", int),
        # 초로 적은 운동 시간(#2546). 없으면 앱이 `minutes` 로 읽는다.
        duration_seconds=_num("duration_seconds", int),
        weight=_num("weight", float),
        intensity=intensity if isinstance(intensity, str) and intensity else None,
        done=raw.get("done") is not False,
    )


def history_exercise_line(raw: object) -> str:
    """저장된 이력 한 줄 → `exercises` 에 싣는 문장.

    옛 행은 문장 그대로다. 값으로 저장한 행(#2546)은 저장할 때 만든 문장
    (`label`)을 쓰고, 그것도 없으면 이름만 둔다.
    """
    if isinstance(raw, dict):
        label = raw.get("label")
        return label if isinstance(label, str) and label else str(raw.get("name") or "")
    return str(raw or "")


def relative_time_label(ts: datetime) -> str:
    """채팅 최근시각 → 오늘이면 HH:MM, 어제면 '어제', 그 전이면 YYYY-MM-DD.

    카카오톡과 같은 규칙이다. 예전에는 "방금/N분 전/N시간 전/N일 전" 으로
    흘러간 시간을 셌는데, 며칠씩 지난 대화에서 트레이너가 알고 싶은 것은
    "얼마나 됐나" 가 아니라 **언제였나** 다 — 그건 운동·식단 기록과 맞춰
    보려면 날짜여야 한다.

    경계는 **KST 달력 날짜**로 가른다. 흘러간 초로 나누면 KST 새벽 1시에
    받은 메시지가 23시간 전이라는 이유로 '오늘' 이 아니게 된다.
    """
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    local = clock.to_seoul(ts)
    today = clock.today()
    days = (today - local.date()).days
    if days <= 0:
        return local.strftime("%H:%M")
    if days == 1:
        return "어제"
    return local.date().isoformat()


def _local_date_iso(ts: datetime) -> str:
    """tz-aware(또는 naive=UTC 가정) 시각 → KST 날짜 YYYY-MM-DD.

    created_at 은 UTC 로 저장되므로, '오늘/어제' 판정과 맞추려면 KST 날짜로 변환해야
    한다(안 그러면 KST 새벽엔 UTC 가 전날이라 '어제'로 어긋난다)."""
    return clock.to_seoul(ts).date().isoformat()


def _sodium_week(diet_rows: list[DietEntry], monday: date) -> list[int]:
    """이번 주(월→일) 일별 나트륨 합. 기록 없는 날은 0."""
    return [
        round(v) for v in _daily_week(diet_rows, monday, lambda e: e.sodium_mg)
    ]


def _calories_week(diet_rows: list[DietEntry], monday: date) -> list[int]:
    """이번 주(월→일) 일별 칼로리 합. 나트륨과 같은 창·같은 규칙이다. (#746)"""
    return [
        round(v)
        for v in _daily_week(diet_rows, monday, lambda e: e.total_calories)
    ]


def _sugar_week(diet_rows: list[DietEntry], monday: date) -> list[float]:
    """이번 주(월→일) 일별 당류 합.

    나트륨·칼로리와 달리 소수를 유지한다 — 당류는 6.3+8.5 처럼 소수로 쌓이고,
    반올림하면 같은 회원의 식단 탭 수치와 어긋난다(`sugar_g` 가 Float 인 이유와
    같다).
    """
    return [round(v, 1) for v in _daily_week(diet_rows, monday, lambda e: e.sugar_g)]


def _macro_week(
    diet_rows: list[DietEntry], monday: date, value: Callable[[DietEntry], float]
) -> list[float]:
    """이번 주(월→일) 일별 탄·단·지 합. 당류와 같이 소수를 유지한다.

    트레이너 화면의 `이번 달` 칼로리 막대를 탄단지로 쌓는 재료다(#944). 칼로리와
    같은 창·같은 규칙이라 x 축이 어긋나지 않는다.
    """
    return [round(v, 1) for v in _daily_week(diet_rows, monday, value)]


def _daily_week(
    diet_rows: list[DietEntry], monday: date, value: Callable[[DietEntry], float]
) -> list[float]:
    """이번 주(월→일) 일별 합. 기록 없는 날과 아직 오지 않은 날은 0.

    `week_completion` 과 **같은 창**이다. 오늘 기준 롤링 7일이 아니라 요일에
    고정한다 — 화면이 이 값을 요일 라벨과 함께 그리므로, 창이 굴러가면 금요일
    수치가 일요일 자리에 놓인다(#746).
    """
    by_date: dict[str, float] = {}
    for e in diet_rows:
        by_date[e.date] = by_date.get(e.date, 0) + value(e)
    return [
        by_date.get((monday + timedelta(days=off)).isoformat(), 0)
        for off in range(7)
    ]


def week_completion_by_member(
    db: Session, trainer_id: str, member_ids: Sequence[str], monday: date
) -> dict[str, list[int | None]]:
    """그 주(월→일) 회원별 요일 이행률(0..100). (#2513)

    그날 이행률 = (완료한 개인운동 + 완료한 PT) ÷ (그날 걸린 개인운동 + 그날
    잡힌 PT). 예전에는 `routine_history` 의 그날 최댓값이었는데, 운영 코드에서 그
    표에 쓰는 곳은 PT 완료 하나뿐이라 값이 사실상 "PT 를 했으면 100" 이었다 —
    회원이 개인운동을 매일 해도 PT 없는 날은 `기록 없음` 으로 그려졌다.

    - 개인운동은 회원 화면과 같은 규칙([_routine_items_on])으로 센다. 다음 날
      이후에 체크한 것도 완료다. 새 개인운동이 온 날 이미 한 옛 것도 그날 칸에
      남는다.
    - PT 는 이 트레이너의 예정·완료만 분모다. 취소·노쇼는 트레이너 사정일 수
      있어 세지 않고(#871), 상담도 PT 가 아니다(#2741).
    - **직접 추가한 운동은 넣지 않는다.** 해야 할 목록(분모)이 없고, 넣으면 받은
      개인운동을 빼먹고 다른 운동을 해도 100% 가 되어 "준 운동을 하고 있나" 가
      가려진다.

    아무것도 걸리지 않은 날과 아직 오지 않은 날은 null 이다. 0 은 "걸렸는데
    하나도 안 했다" 라는 다른 뜻이다. 쿼리는 회원 수와 무관하게 셋이다.
    """
    out: dict[str, list[int | None]] = {m: [None] * 7 for m in member_ids}
    end = min(monday + timedelta(days=6), clock.today())
    if not member_ids or end < monday:
        return out
    monday_iso, end_iso = monday.isoformat(), end.isoformat()
    rows = db.scalars(
        select(TrainerRoutine)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id.in_(member_ids),
            TrainerRoutine.status == ROUTINE_APPROVED,
            TrainerRoutine.active_from <= end_iso,
            or_(
                TrainerRoutine.ended_on.is_(None),
                TrainerRoutine.ended_on >= monday_iso,
            ),
        )
        .order_by(TrainerRoutine.sort_order, TrainerRoutine.created_at)
    ).all()
    rows_by_member: dict[str, list[TrainerRoutine]] = defaultdict(list)
    for row in rows:
        rows_by_member[row.member_id].append(row)
    done: dict[tuple[str, date], ExerciseSession] = {}
    if rows:
        for session in db.scalars(
            select(ExerciseSession).where(
                ExerciseSession.assigned_routine_id.in_([r.id for r in rows]),
                ExerciseSession.week_start == monday_iso,
            )
        ).all():
            day = exercise_activity.activity_date_of(session)
            if day is not None and monday <= day <= end:
                done[(session.assigned_routine_id, day)] = session
    pt: dict[tuple[str, str], list[int]] = {}
    for session in db.scalars(
        select(TrainerSchedule).where(
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.member_id.in_(member_ids),
            TrainerSchedule.date >= monday_iso,
            TrainerSchedule.date <= end_iso,
            TrainerSchedule.status.in_((SCHEDULE_UPCOMING, SCHEDULE_DONE)),
            TrainerSchedule.type != "상담",
        )
    ).all():
        counts = pt.setdefault((session.member_id or "", session.date), [0, 0])
        counts[0] += 1
        if session.status == SCHEDULE_DONE:
            counts[1] += 1
    for member_id in member_ids:
        week = out[member_id]
        for offset in range(7):
            day = monday + timedelta(days=offset)
            if day > end:
                break
            items = _routine_items_on(
                rows_by_member.get(member_id, []), done, day,
                keep_done_on_end_day=True,
            )
            booked, pt_done = pt.get((member_id, day.isoformat()), (0, 0))
            total = len(items) + booked
            if total == 0:
                continue
            finished = sum(1 for item in items if item.done) + pt_done
            week[offset] = round(100 * finished / total)
    return out


def _week_days(
    rows: list[ExerciseSession],
    week: list[int | None],
    assigned: list[int | None] | None = None,
) -> list[WeeklyReportDayOut]:
    """요일별 이행률 + 그날 **실제로 한** 운동(월→일).

    운동 이름은 회원의 운동 기록에서 온다 — 배정 목록이 아니다(#1288). 예전에는
    `routine_history` 를 읽었는데, 그 표에 쓰는 경로는 PT 세션 완료 하나뿐이라
    PT 한 날 말고는 요일 칸이 늘 비어 있었다. 배정 루틴 수행도 회원이 혼자 한
    운동도 전부 `exercise_sessions` 로 가므로, 읽을 곳은 여기다.

    **미수행(✗) 표시를 붙이지 않는다.** 배정에는 날짜가 없어 — `exercise_date`
    를 채우는 생성 경로가 없고 회원 목록에도 날짜 필터가 없다 — "그날 배정됐는데
    안 했다" 를 만들 수 없다. 그날 남은 기록만 적는다.

    [rows] 는 한 주치 기록이다. 운동 기록은 날짜가 아니라 (그 주 월요일, 요일)
    로 저장되므로 요일 라벨만으로 자리가 정해진다.

    [assigned] 는 요일별 그날 걸려 있던 추천 개인운동 수다(#2772,
    [_assigned_week]). 모르는 날은 null 로 둔다.
    """
    by_weekday: dict[int, list[str]] = {}
    for row in rows:
        if row.day_label not in exercise_service.WEEKDAY_LABELS:
            continue
        # 이름이 빈 기록은 그 컬럼이 생기기 전(#1276)의 것이다. 유형 라벨이라도
        # 적어야 그날 무엇을 했는지가 칸에서 통째로 사라지지 않는다.
        # 라벨은 요청 언어로 고른다(#2885) — 영어 리포트에 `근력` 이 남지 않게.
        name = (row.name or "").strip() or exercise_types.normalize_label(
            row.type, current_locale()
        )
        by_weekday.setdefault(
            exercise_service.WEEKDAY_LABELS.index(row.day_label), []
        ).append(name)
    return [
        WeeklyReportDayOut(
            completion=week[i] if i < len(week) else None,
            exercises=by_weekday.get(i, []),
            assigned=assigned[i] if assigned and i < len(assigned) else None,
        )
        for i in range(7)
    ]


def _meal_counts(diet_rows: list[DietEntry], monday: date) -> list[int]:
    """그 주(월→일) 요일별 끼니 기록 수 — 그날 `DietEntry` 수. (#2772)

    칼로리·나트륨과 **같은 창**이다. 기록 없는 날과 아직 오지 않은 날은 0 이다.
    """
    by_date: dict[str, int] = {}
    for e in diet_rows:
        by_date[e.date] = by_date.get(e.date, 0) + 1
    return [
        by_date.get((monday + timedelta(days=off)).isoformat(), 0)
        for off in range(7)
    ]


def _assigned_week(
    db: Session, trainer_id: str, member_id: str, monday: date
) -> list[int | None]:
    """그 주(월→일) 요일별로 그날 걸려 있던 추천 개인운동 수. (#2772)

    추천 개인운동은 매일 리셋되는 목록이라(#2161) 그날의 분모는 "그날 걸려
    있던 배정" 이다 — 회원 화면과 같은 규칙인 [member_routine_days] 로 센다.
    리포트를 쓰는 트레이너의 배정만 센다.

    배정이 하나도 없던 날과 아직 오지 않은 날은 null 이다. 0 은 쉬는 날과
    구분되지 않아 쓰지 않는다 — 화면이 `0 / 0` 을 그리면 안 한 날처럼 읽힌다
    (#2232, 데모 `assignedCount` 와 같은 규칙).
    """
    out: list[int | None] = [None] * 7
    for day in member_routine_days(
        db, member_id, monday, monday + timedelta(days=6), trainer_id=trainer_id
    ):
        offset = (day.date - monday).days
        if 0 <= offset < 7 and day.routines:
            out[offset] = len(day.routines)
    return out


def _roster_active(link: TrainerClient) -> bool:
    """로스터 카드의 활성/휴면. (#707)

    두 조건을 모두 만족해야 활성이다 — 담당 관계가 살아 있고(`active`), 트레이너가
    휴면으로 내리지 않았을 것(`not dormant`). 담당이 해제된 과거 회원은 로스터에
    이력으로 남는데, 그 카드는 예나 지금이나 휴면으로 보여야 한다.
    """
    return link.active and not link.dormant


def _iso(ts: datetime) -> str:
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    return ts.astimezone(timezone.utc).isoformat()


def _roster_preview(msg: ChatMessage | None) -> str:
    """로스터의 마지막 메시지 한 줄.

    사진만 보낸 메시지는 본문이 비어 있다(#921, #1665). 그대로 두면 회원이 사진을
    보낸 직후 목록의 미리보기가 빈칸이 되어, 무엇이 왔는지 대화를 열어야 안다.
    """
    if msg is None:
        return ""
    if not msg.body and msg.attachment_type == "image" and msg.attachment_file_id:
        return localized("사진", "Photo")
    return msg.body


class ClientLinkDetached(Exception):
    """담당 관계가 이미 해제된 회원이다.

    활성/휴면 전환·재등록에서는 409, 해제된 회원에게 무언가를 보내려는 경로
    (`send_session_program`)에서는 남의 회원과 같은 404 로 옮긴다.
    """


def has_active_client_link(db: Session, trainer_id: str, member_id: str) -> bool:
    """(trainer, member) 담당 관계가 살아 있고 열람 동의가 있는가. (#2281)

    링크 행은 해제 뒤에도 남으므로(`remove_client`) 행 존재만으로는 담당이
    아니다. 라우터의 `_require_client` 를 지나지 않는 경로(제안 승인·일정의
    프로그램·개인운동 전송·완료 등)가 이 함수로 같은 경계를 본다.

    동의가 철회된 뒤 새 동의 없이 살아 있는 링크도 `_require_client` 처럼
    막는다(#1631) — 한쪽만 동의를 보면 같은 회원이 경로에 따라 열리고 닫힌다.
    """
    return db.scalar(
        select(TrainerClient.id).where(
            TrainerClient.trainer_id == trainer_id,
            TrainerClient.member_id == member_id,
            data_consent_service.open_link_clause(),
        )
    ) is not None


def _ensure_session_member_linked(
    db: Session, trainer_id: str, s: TrainerSchedule
) -> None:
    """일정에 붙은 회원이 아직 담당·동의 경계 안인지 본다. 아니면 [ClientLinkDetached].

    일정 id 로 여는 경로는 `_get_owned_session`(내 일정인가)만 보므로, 해제 전에
    잡아 둔 일정으로 해제된 회원의 운동 기록을 쓰거나 알림을 보낼 수 있었다.
    해제된 회원의 일정은 스케줄에 익명 기록으로만 남으므로(#2589) 남의 회원과
    같은 404 로 옮긴다. 회원이 없는 일정(상담·공백)은 지나간다.

    상담 요청으로 생긴 일정도 지나간다(#2584) — 수락은 담당 연결을 만들지 않아,
    연결 전 회원과의 상담을 완료하거나 상담 메모를 적을 수 있어야 한다. 상담은
    완료해도 운동 기록을 만들지 않고(`_SESSION_EXERCISE_TYPE`), 메모는 트레이너만
    본다. 스케줄의 익명 처리(`_schedule_outs`)와 같은 경계다(`_is_consultation_booking`).

    취소·삭제는 이 확인을 하지 않는다 — 잡혀 있던 약속이 없어졌다는 통보는
    해제 뒤에도 회원이 알아야 하는 정리다.
    """
    if _is_consultation_booking(s):
        return
    if s.member_id and not has_active_client_link(db, trainer_id, s.member_id):
        raise ClientLinkDetached("담당 고객을 찾을 수 없습니다.")


#: 담당 해제로 거둔 일정에 남기는 취소 사유(#2589). 트레이너만 보는 기록이다.
DETACH_CANCEL_REASON = "담당 해제"


def sessions_cancelled_on_detach(
    db: Session, trainer_id: str, member_id: str
) -> list[TrainerSchedule]:
    """담당이 끊기면 취소할 일정 — 이 쌍의 `예정` 중 아직 시작하지 않은 것. (#2589)

    시작 시각이 지난 `예정` 은 남긴다. 실제로 했을 수 있는 수업이라 취소로 덮으면
    지난 기록이 틀어진다 — 익명 기록으로 스케줄에 남는다.
    """
    now = clock.now()
    today = now.date().isoformat()
    minute = now.hour * 60 + now.minute
    rows = db.scalars(
        select(TrainerSchedule)
        .where(
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.member_id == member_id,
            TrainerSchedule.status == SCHEDULE_UPCOMING,
            TrainerSchedule.date >= today,
        )
        .order_by(TrainerSchedule.date, TrainerSchedule.time, TrainerSchedule.id)
    ).all()

    def not_started(s: TrainerSchedule) -> bool:
        if s.date > today:
            return True
        try:
            return _clock_minutes(s.time) > minute
        except ValueError:
            return False

    # 회원이 직접 신청한 상담은 담당과 별개다(#2584) — 해제해도 거두지 않는다.
    return [s for s in rows if not_started(s) and not _is_consultation_booking(s)]


def _cancel_sessions_on_detach(
    db: Session, trainer_id: str, member_id: str, *, source: str
) -> int:
    """담당이 끊긴 쌍의 남은 일정을 취소한다(커밋 없음). 취소한 수. (#2589)

    담당이 끝났으니 남은 PT 는 열리지 않는다. 그대로 두면 트레이너 스케줄에는
    익명 일정이 자리를 차지하고, 회원 앱에는 끊긴 트레이너와의 수업이 남는다.
    예약으로 생긴 일정은 [cancel_session] 처럼 예약을 거두고 좌석을 돌려준다.
    일정별 취소 알림은 보내지 않는다 — 해제 알림 한 건이 대신한다.
    """
    rows = sessions_cancelled_on_detach(db, trainer_id, member_id)
    if not rows:
        return 0
    cancelled_at = datetime.now(timezone.utc)
    for s in rows:
        s.status = SCHEDULE_CANCELLED
        s.cancelled_at = cancelled_at
        s.cancellation_source = source
        s.cancellation_reason = DETACH_CANCEL_REASON
    db.flush()
    for s in rows:
        _release_cancelled_reservation(db, s, source=source)
    return len(rows)


#: 배정 행의 검토 상태. AI 후보는 pending 으로 들어와 트레이너 판단을 기다린다.
#:
#: 기본이 approved 인 이유는 하위 호환이다 — 이 값이 생기기 전의 배정은 모두
#: 트레이너가 보낸 것이므로 그대로 회원에게 보여야 한다.
ROUTINE_APPROVED = "approved"


ROUTINE_PENDING = "pending"
#: PT 일정에 붙여 두었고 아직 회원에게 보내지 않은 개인운동(#2223). 회원에게
#: 가는 것은 그 PT 를 완료할 때다(#2224). `pending` 과 나눠 두는 이유는 저쪽이
#: **트레이너가 승인할지 판단할 후보**라는 것이다 — 이쪽은 이미 정해진 운동이고,
#: 제안 검토 목록에 섞이면 트레이너가 같은 운동을 두 번 검토하게 된다.
ROUTINE_SCHEDULED = "scheduled"


ROUTINE_DISMISSED = "dismissed"
#: 프로그램 만들기의 개인운동 단계를 채웠고 그 전송에 실려 나간 AI 제안(#2747).
#: 회원이 받는 것은 전송이 새로 만든 배정 행이고, 이 행은 "어느 제안이 그 전송의
#: 출처였나" 만 남긴다. `approved` 로 두면 같은 운동이 회원 목록에 두 벌 걸리고,
#: `dismissed` 로 두면 "추천하지 않기로 함" 과 뜻이 섞인다.
ROUTINE_CONSUMED = "consumed"


ROUTINE_STATUSES = frozenset(
    {
        ROUTINE_APPROVED,
        ROUTINE_PENDING,
        ROUTINE_SCHEDULED,
        ROUTINE_DISMISSED,
        ROUTINE_CONSUMED,
    }
)

#: 전송 종류(#2223, #2225). 개인운동 행에 남겨 이력이 "무엇과 함께 갔는지" 를
#: 말할 수 있게 한다.
DELIVERY_PT_WITH_ROUTINE = "pt_with_routine"


DELIVERY_ROUTINE_ONLY = "routine_only"


DELIVERY_CANCELLED_ROUTINE_ONLY = "cancelled_routine_only"


def _day_start(day: str) -> datetime | None:
    """`YYYY-MM-DD` → 그날 0시. 형식이 틀리면 None.

    이 표는 시각 없이 날짜만 들고 있다. 받는 쪽은 시각을 버리고 날짜만 보므로
    (`historyInRange`) 0시로 세워도 뜻이 달라지지 않는다.
    """
    try:
        return datetime.fromisoformat(f"{day}T00:00:00")
    except ValueError:
        return None


def _apply_routine_duration(
    row: TrainerRoutine,
    *,
    minutes: int | None,
    duration_seconds: int | None,
) -> None:
    """고친 운동 시간을 배정 행에 반영한다 — 분과 초를 한 값으로 맞춘다. (#2547)

    초를 보내면 초가 기준이고 분은 거기서 접는다. 분만 보내면 예전 초를 지운다 —
    [_routine_seconds] 가 초를 먼저 읽으므로, 남겨 두면 `45초` 배정의 분을 5로
    고쳐도 계속 `45초` 로 읽혔다. 초가 비면 분 × 60 으로 읽힌다.

    둘 다 없으면 시간은 그대로다. 유형은 **고친 뒤의** 값으로 본다 — 근력은
    세트로 재므로 초를 두지 않는다.
    """
    if duration_seconds is not None:
        row.duration_seconds = duration_seconds
        row.minutes = _minutes_of(duration_seconds)
    elif minutes is not None:
        row.minutes = minutes
        row.duration_seconds = None
    if row.type == "근력":
        row.duration_seconds = None


def _routine_seconds(rt: TrainerRoutine) -> int | None:
    """배정 한 건의 운동 시간(초). 근력은 세트로 재므로 없다. (#2221)

    초를 적지 않은 예전 배정은 분 × 60 으로 채운다 — 읽는 쪽이 두 단위를 오가지
    않고 초 하나만 믿으면 되게 한다(프로그램 운동의 `duration_seconds` 와 같다).
    """
    if rt.type == "근력":
        return None
    seconds = getattr(rt, "duration_seconds", None)
    return seconds if seconds is not None else rt.minutes * 60


def _member_goals(db: Session, member_id: str) -> str:
    """회원 건강 목표(쉼표로 이은 저장값). 프로필이 없으면 빈 값."""
    return (
        db.scalar(
            select(HealthProfile.conditions).where(
                HealthProfile.user_id == member_id
            )
        )
        or ""
    )


@dataclass
class _RoutineOutPrefetch:
    """목록 응답에서 행마다 다시 읽던 회원 값을 한 번에 읽어 둔 것. (#2911)

    [_routine_out] 은 행마다 회원 체중(예상 소모 칼로리)과 건강 목표(효과 문구)를
    읽는다. 한 일정·한 회원의 목록인데 행 수만큼 같은 조회가 반복됐다. 목록
    경로는 [_routine_prefetch] 로 회원별 값을 `IN (...)` 한 번씩 읽어 넘긴다.
    같은 이름·유형·시간·강도·체중의 예상 칼로리도 한 번만 계산한다.
    """

    goals: dict[str, str]
    weights: dict[str, float | None]
    estimates: dict[tuple, Any]


def _routine_prefetch(
    db: Session, rows: Sequence[TrainerRoutine]
) -> _RoutineOutPrefetch:
    member_ids = sorted({rt.member_id for rt in rows if rt.member_id})
    goals: dict[str, str] = {member_id: "" for member_id in member_ids}
    weights: dict[str, float | None] = {member_id: None for member_id in member_ids}
    if member_ids:
        for user_id, conditions, weight_kg in db.execute(
            select(
                HealthProfile.user_id,
                HealthProfile.conditions,
                HealthProfile.weight_kg,
            ).where(HealthProfile.user_id.in_(member_ids))
        ).all():
            goals[user_id] = conditions or ""
            weights[user_id] = weight_kg
    return _RoutineOutPrefetch(goals=goals, weights=weights, estimates={})


def _routine_outs(
    db: Session, rows: Sequence[TrainerRoutine]
) -> list[RoutineOut]:
    """여러 행의 응답 — 회원 값은 한 번만 읽는다(#2911)."""
    prefetch = _routine_prefetch(db, rows)
    return [_routine_out(db, rt, prefetch=prefetch) for rt in rows]


def _routine_effect(
    db: Session, rt: TrainerRoutine, goals: str | None = None
) -> str:
    """배정 한 건의 효과 한 줄 — 적힌 값, 없으면 문구표. (#2570)

    저장은 트레이너가 적은 것만 한다. 자동 문구를 저장해 두지 않고 응답 때
    채우는 이유는 두 가지다: 배정 길이 여럿(단일 배정·AI 제안·자동 추천·
    프로그램·일정 개인운동)이라 한 곳에서 채워야 빠짐이 없고, 회원이 목표를
    바꾸면 문구도 따라가야 한다.

    운동 여럿으로 짠 세션은 한 유형의 효과로 말할 수 없어 비운다.
    """
    written = (getattr(rt, "effect", "") or "").strip()
    if written:
        return written
    if len(draft_exercises(rt.exercises_json)) > 1:
        return ""
    return routine_effects.auto_routine_effect(
        rt.type, goals if goals is not None else _member_goals(db, rt.member_id)
    )


def _routine_out(
    db: Session,
    rt: TrainerRoutine,
    completion: ExerciseSession | None = None,
    *,
    include_evidence: bool = True,
    prefetch: _RoutineOutPrefetch | None = None,
) -> RoutineOut:
    """루틴 한 건의 응답.

    [include_evidence] 를 끄면 근거를 싣지 않는다 — 회원에게 가는 응답이다.
    근거(`최근 근력운동 비중 높음`)는 트레이너가 승인 여부를 판단하는 재료이지
    회원이 읽을 문구가 아니다. 화면이 감추는 것과 응답에 담지 않는 것은 다르다
    (#790).

    `db` 를 받는 이유는 예상 소모 칼로리 때문이다(#1312). 이 값은 루틴 이름과
    **그 회원의 체중**에서 나오므로, 유형·시간만 보던 때와 달리 조회가 필요하다.
    트레이너 화면의 읽기 전용 미리보기와 회원 화면의 값이 같아야 하니 계산은
    회원 앱과 같은 한 곳(`exercise_service.estimate`)을 쓴다.
    """
    intensity = getattr(rt, "intensity", None) or "moderate"
    if prefetch is not None and rt.member_id in prefetch.weights:
        weight_kg = prefetch.weights[rt.member_id]
        goals: str | None = prefetch.goals[rt.member_id]
    else:
        weight_kg = exercise_service.member_weight_kg(db, rt.member_id)
        goals = None
    estimate_key = (rt.name, rt.type, rt.minutes, intensity, weight_kg)
    estimated = (
        prefetch.estimates.get(estimate_key) if prefetch is not None else None
    )
    if estimated is None:
        estimated = exercise_service.estimate(
            db,
            name=rt.name,
            type_=rt.type,
            minutes=rt.minutes,
            intensity=intensity,
            weight_kg=weight_kg,
            # 목록을 그릴 때마다 루틴 수만큼 외부 호출이 일어나면 트레이너 화면이
            # 멈춘다. 이름 해석은 회원이 저장할 때 이미 캐시에 들어가므로, 여기서는
            # 표 매칭과 캐시까지만 본다.
            use_ai=False,
        )
        if prefetch is not None:
            prefetch.estimates[estimate_key] = estimated
    return RoutineOut(
        id=rt.id, name=rt.name, minutes=rt.minutes, type=rt.type,
        exercise_date=getattr(rt, "exercise_date", None),
        intensity=intensity,
        sets=getattr(rt, "sets", None),
        reps=getattr(rt, "reps", None),
        hold_seconds=getattr(rt, "hold_seconds", None),
        duration_seconds=_routine_seconds(rt),
        weight=getattr(rt, "weight", None),
        # 예상 소모 칼로리 — 트레이너가 고른 강도로 계산한다. 회원이 수행을
        # 마치면 그때의 강도로 다시 계산한 값이 운동 기록에 남는다. (#996)
        calories=estimated.calories,
        calorie_source=estimated.source,
        # AI 제안(근거가 있는 행)의 사유는 트레이너가 읽는 판단 재료라 회원
        # 응답에 싣지 않는다(#2579). 회원 카드에는 효과 한 줄이 선다.
        reason=(
            rt.reason
            if include_evidence or not suggestion_evidence(rt.evidence_json)
            else ""
        ),
        source=rt.source,
        effect=_routine_effect(db, rt, goals),
        program_name=rt.program_name,
        session_name=rt.session_name,
        session_order=rt.session_order,
        exercises=draft_exercises(rt.exercises_json),
        evidence=(
            suggestion_evidence(rt.evidence_json) if include_evidence else []
        ),
        completed=completion is not None,
        completed_at=completion.completed_at if completion is not None else None,
        completed_minutes=completion.minutes if completion is not None else None,
        completed_duration_seconds=(
            completion.duration_seconds if completion is not None else None
        ),
        completed_intensity=completion.intensity if completion is not None else None,
        # 개인 운동 회원 피드백은 없앴다(#1825). 응답 모양은 옛 앱을 위해 남긴다.
        member_note="",
        # 개인 운동 트레이너 피드백도 없앴다(#2517). 응답 모양은 옛 앱을 위해 남긴다.
        trainer_feedback="",
        schedule_id=getattr(rt, "schedule_id", None),
        pending_send=getattr(rt, "status", "") == ROUTINE_SCHEDULED,
        delivery_kind=getattr(rt, "delivery_kind", None),
        trainer_message=getattr(rt, "trainer_message", "") or "",
    )


def _consume_routine_suggestions(
    db: Session,
    trainer_id: str,
    member_id: str,
    suggestion_ids: Sequence[str],
) -> None:
    """전송에 실려 나간 대기 제안을 닫는다(#2747). **커밋하지 않는다.**

    배정을 만드는 쪽과 같은 트랜잭션이어야 한다 — 전송이 실패하면 제안도 대기로
    남아 트레이너가 다시 보낼 수 있다. 이 트레이너·이 회원의 **대기 중** 제안만
    닫고 나머지 id(남의 것·없는 것·이미 검토한 것)는 조용히 무시한다: 같은
    위저드를 두 창에서 열어 한쪽이 먼저 보냈을 때 다른 쪽 전송까지 막을 까닭이
    없다.
    """
    ids = list(dict.fromkeys(i for i in suggestion_ids if i))
    if not ids:
        return
    db.execute(
        update(TrainerRoutine)
        .where(
            TrainerRoutine.id.in_(ids),
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
            TrainerRoutine.status == ROUTINE_PENDING,
        )
        .values(
            status=ROUTINE_CONSUMED,
            reviewed_at=clock.now(),
            reviewed_by=trainer_id,
        )
        .execution_options(synchronize_session=False)
    )


def _assigned_history_out(row: ExerciseSession) -> RoutineHistoryOut:
    """배정 루틴 수행 → 트레이너 이력 계약."""
    completed_at = row.completed_at or row.created_at
    # 라벨의 날짜는 [build_client_history] 와 같은 규칙을 쓴다(#1264). 두 곳이
    # 갈리면 같은 기록이 목록과 상세에서 다른 날로 보인다.
    day = (
        exercise_activity.activity_date_of(row)
        or clock.to_seoul(completed_at).date()
    ).isoformat()
    label = row.assigned_routine_name or ASSIGNED_HISTORY_FALLBACK_LABEL
    return RoutineHistoryOut(
        id=row.id,
        date_label=history_date_label(day),
        label=label,
        completion_rate=100,
        exercises=[
            f"{row.assigned_routine_name or row.type} · "
            + _amount_label(
                row.type, minutes=row.minutes,
                duration_seconds=row.duration_seconds,
                sets=row.sets, reps=row.reps, hold_seconds=row.hold_seconds,
                weight=row.weight,
            )
            + f" · {row.intensity}"
        ],
        date=day,
        # 이름이 있으면 트레이너가 지은 이름이라 코드가 없다.
        kind=None if row.assigned_routine_name else "assigned_routine",
        exercise_items=[_assigned_exercise_item(row)],
        # 개인 운동 피드백은 회원(#1825)·트레이너(#2517) 모두 없앴다. 응답 모양만 남긴다.
        client_feedback="",
        trainer_note="",
        assigned_routine_id=row.assigned_routine_id,
        completed_at=completed_at,
    )


def _assigned_exercise_item(row: ExerciseSession) -> RoutineHistoryExerciseOut:
    """배정 수행 한 건 → 값으로 나눈 운동 한 종목(#2300).

    `exercises` 문장과 같은 규칙이다([_amount_label]) — 근력은 세트·횟수(또는
    버틴 초)·중량, 나머지와 세트가 없던 옛 근력 배정은 분.

    시간으로 재는 수행은 회원이 남긴 초(`duration_seconds`)도 싣는다(#2221) —
    분만 보내면 `45초` 수행이 트레이너 이력에 `1분` 으로 보인다. 문장도 초까지
    적는다(#2546) — 이 문장은 되읽지 않고 이 값이 함께 간다.
    """
    type_code = exercise_types.normalize(row.type)
    strength = type_code == exercise_types.STRENGTH and row.sets is not None
    return RoutineHistoryExerciseOut(
        name=row.assigned_routine_name or row.type,
        type=type_code,
        minutes=0 if strength else row.minutes,
        sets=row.sets if strength else None,
        reps=row.reps if strength and not row.hold_seconds else None,
        hold_seconds=row.hold_seconds if strength and row.hold_seconds else None,
        duration_seconds=None if strength else row.duration_seconds,
        weight=row.weight if strength else None,
        intensity=row.intensity or None,
    )


def _session_summary(
    exercises: Sequence[ProgramDraftExercise],
) -> tuple[int, str, str]:
    """세션 하나를 루틴 한 건의 (분, 유형, 출처)로 요약한다. (#709)

    트레이너 웹이 단일 세션을 배정할 때 쓰던 규칙과 같다 — 분은 각 운동의
    `duration` 합, 유형은 가장 많은 유형, 출처는 AI 제안이 하나라도 있으면
    'ai'. 규칙을 서버로 옮긴 것은 세션이 여러 개가 되면서 클라이언트마다
    다르게 접히는 것을 막기 위해서다.

    근력은 시간을 적지 않으므로 세트에서 환산한다 — `_program_seconds_and_type`
    과 같은 값이라야 배정과 PT 완료가 같은 분을 센다(#1276).

    시간은 초로 더한 뒤 한 번만 분으로 접는다(#2221) — 45초짜리 셋을 각각 1분으로
    올려 더하면 2분 15초가 3분이 된다.
    """
    counts: dict[str, int] = {}
    has_ai = False
    for exercise in exercises:
        counts[exercise.type] = counts.get(exercise.type, 0) + 1
        if exercise.source == "ai":
            has_ai = True
    type_ = max(counts, key=lambda t: counts[t]) if counts else "근력"
    return _minutes_of(_session_seconds(exercises)), type_, ("ai" if has_ai else "trainer")


def _session_seconds(exercises: Sequence[ProgramDraftExercise]) -> int:
    """세션 하나의 운동 시간(초) — 각 운동의 초를 더한 값이다. (#2221)

    배정 행의 `duration_seconds` 로도 남긴다(#2521). 분만 남기던 동안에는 읽는
    쪽이 분 × 60 으로 되짚어, 45초짜리 운동 하나인 세션이 60초로 읽혔다.
    """
    return sum(
        _exercise_seconds(e.type, e.duration_seconds, e.sets) for e in exercises
    )


def _exercise_seconds(type_: str, duration_seconds: int | None, sets: int | None) -> int:
    """운동 한 항목이 차지하는 시간(초). 근력은 적은 시간이 없어 세트에서 환산한다.

    회원 기록이 세트를 분으로 되짚는 것과 같은 값(세트당 3분)이라야 두 집계가
    어긋나지 않는다(#1276).
    """
    if duration_seconds:
        return duration_seconds
    if type_ == "근력" and sets:
        return round(sets * exercise_service.STRENGTH_MINUTES_PER_SET) * 60
    return 0


def _minutes_of(seconds: int) -> int:
    """초를 분으로 접는다 — 0 이 아니면 최소 1분(`ExerciseSessionCreate` 와 같다)."""
    return max(1, round(seconds / 60)) if seconds > 0 else 0


def _program_request_key(base: str, index: int) -> str:
    """세션별 멱등키. 프로그램 전체가 한 번의 전송 시도이므로 같은 base 를 쓴다.

    세션마다 키를 나누는 이유는 `(trainer, member, client_request_id)` 유니크
    제약 때문이다 — 같은 키로 여러 행을 만들 수 없다.
    """
    return f"{base}#{index}"


def _program_routines_for_request(
    db: Session, trainer_id: str, member_id: str, client_request_id: str,
    session_count: int,
) -> list[TrainerRoutine]:
    """그 멱등키로 이미 배정된 세션 루틴들(세션 순서대로). 없으면 빈 목록."""
    return list(
        db.scalars(
            select(TrainerRoutine)
            .where(
                TrainerRoutine.trainer_id == trainer_id,
                TrainerRoutine.member_id == member_id,
                TrainerRoutine.client_request_id.in_(
                    [
                        _program_request_key(client_request_id, index)
                        for index in range(session_count)
                    ]
                ),
            )
            .order_by(TrainerRoutine.session_order)
        ).all()
    )


def _add_program_routines(
    db: Session, trainer_id: str, member_id: str, *,
    name: str,
    sessions: Sequence[ProgramDraftSession],
    client_request_id: str | None,
    delivery_kind: str | None = None,
    trainer_message: str = "",
    start_date: date | None = None,
    active_days: int | None = None,
    status: str = ROUTINE_APPROVED,
    schedule_id: str | None = None,
    notify: bool = True,
    active_from: date | None = None,
) -> list[TrainerRoutine]:
    """세션 루틴과 배정 알림을 세션에 올리고 flush 한다. 커밋은 호출부 몫이다.

    커밋하지 않는 이유는 `일정 추가`(#1580) 때문이다 — 배정과 일정 등록이 한
    트랜잭션이어야 둘 중 하나만 남는 반쪽 상태가 생기지 않는다. 유니크 제약
    위반은 flush 에서 [IntegrityError] 로 올라온다.

    [active_days] 가 오면 그만큼만 회원 목록에 걸어 둔다(#2223) — 배정한 날을
    1일로 세어 `ended_on` 을 찍는다. 비우면 철회할 때까지 걸려 있다(#2161).

    [status] 를 `scheduled` 로 주면 **회원에게 보이지 않는다**(#2279). PT 일정에
    붙는 프로그램이 그렇다 — 개인운동과 같이 붙여만 두었다가 PT 를 마치고
    보낼 때 함께 올라간다. 그때는 [schedule_id] 로 어느 PT 의 것인지 묶고,
    [notify] 를 내려 배정 알림도 미룬다: 지금 알리면 회원은 아직 오지 않은
    운동의 알림을 먼저 받는다.

    [active_from] 은 회원 목록에 걸리는 첫날이다(기본 오늘). `개인운동만` 을
    미래 시작일로 보낼 때 그날을 준다(#2656) — [active_days] 도 그날부터 센다.
    """
    multi = len(sessions) > 1
    today = clock.today()
    begin = active_from or today
    today_iso = begin.isoformat()
    ended_on = (
        (begin + timedelta(days=active_days)).isoformat()
        if active_days is not None
        else None
    )
    max_order = db.scalar(
        select(func.max(TrainerRoutine.sort_order)).where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
        )
    ) or 0
    # 서버 시계([clock])를 따른다 — 보낸 날([routine_sent_on])을 이 시각의 KST
    # 날짜로 읽으므로, 오늘과 다른 시계를 쓰면 '보냄' 날짜가 어긋난다(#2656).
    now = clock.now().astimezone(timezone.utc)
    created: list[TrainerRoutine] = []
    for index, session in enumerate(sessions):
        minutes, type_, source = _session_summary(session.exercises)
        rt = TrainerRoutine(
            id=f"rt-{uuid.uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            name=(session.name or name) if multi else name,
            minutes=minutes,
            # 분은 초에서 한 번 접은 값이다 — 초를 함께 남겨야 45초가 60초로
            # 되짚히지 않는다(#2521). 0 이면(근력만·시간 없음) 비운다.
            duration_seconds=_session_seconds(session.exercises) or None,
            type=type_,
            reason=", ".join(e.name for e in session.exercises)[:200],
            # `개인운동만` 은 세션마다 운동이 하나다 — 그 운동에 적힌 효과가
            # 이 배정의 효과다(#2570). 비면 응답 때 문구표로 채운다.
            effect=(
                session.exercises[0].effect.strip()
                if len(session.exercises) == 1
                else ""
            ),
            source=source,
            program_name=name if multi else "",
            session_name=session.name if multi else "",
            session_order=index,
            exercises_json=json.dumps(
                [e.model_dump(mode="json") for e in session.exercises],
                ensure_ascii=False,
            ),
            sort_order=max_order + index + 1,
            client_request_id=(
                _program_request_key(client_request_id, index)
                if client_request_id
                else None
            ),
            exercise_date=start_date.isoformat() if start_date else None,
            active_from=today_iso,
            ended_on=ended_on,
            status=status,
            schedule_id=schedule_id,
            delivery_kind=delivery_kind,
            trainer_message=trainer_message,
            created_at=now,
        )
        db.add(rt)
        created.append(rt)
    db.flush()

    if not notify:
        return created

    notification_service.queue(
        db,
        member_id=member_id,
        kind=notification_service.EXERCISE,
        category=notification_service.MEMBER_ROUTINE,
        template=notification_templates.MEMBER_ROUTINE_PROGRAM,
        template_args=_program_notification_args(
            name,
            sessions=len(created),
            seconds=sum(_session_seconds(session.exercises) for session in sessions),
            multi=multi,
            routine_only=delivery_kind == DELIVERY_ROUTINE_ONLY,
            starts_on=begin if begin > today else None,
        ),
    )
    return created


def _program_row_seconds(row: TrainerRoutine) -> int:
    """프로그램 세션 한 줄의 시간(초). 운동 구성에서 초로 다시 더한다. (#2546)

    `minutes` 는 세션마다 이미 분으로 접은 값이라 더하면 반올림이 쌓인다. 운동
    구성을 읽을 수 없는 줄만 그 분으로 읽는다.
    """
    exercises = draft_exercises(row.exercises_json)
    if not exercises:
        return row.minutes * 60
    return _session_seconds(exercises)


def _program_notification_args(
    name: str,
    *,
    sessions: int,
    seconds: int,
    multi: bool,
    routine_only: bool = False,
    starts_on: date | None = None,
) -> dict[str, Any]:
    """프로그램 배정 알림의 틀 인자. 합계 시간은 초로 더한 값이다. (#2546)

    세션마다 분으로 접은 뒤 더하면 45초 세션 셋이 `3분` 이 된다(실제 2분 15초).
    `minutes` 는 틀을 모르는 쪽을 위해 같은 합을 한 번만 접어 둔 값이다.

    [routine_only] 는 `개인운동만` 전송이다(#2581) — 프로그램 이름과 `세션 N개`
    대신 `개인운동 N개` 로 말한다.

    [starts_on] 은 미래 시작일로 보낸 개인운동이 걸리기 시작하는 날이다(#2656).
    알림은 지금 가므로, 문구가 그날을 말하지 않으면 회원은 오늘 열어 보고 빈
    목록을 본다.
    """
    args: dict[str, Any] = {
        "name": name,
        "sessions": sessions,
        "seconds": seconds,
        "minutes": _minutes_of(seconds),
        "multi": multi,
        "routine_only": routine_only,
    }
    if starts_on is not None:
        args["starts_on"] = starts_on.isoformat()
    return args


#: 근거 문구 하나의 길이 상한. 스키마
#: (`RoutineSuggestionCreateRequest.evidence`)와 같은 값이다 — 예전 행이나 손으로
#: 고친 값이 화면 한 줄을 넘기지 않게 읽는 쪽에서도 자른다.
_EVIDENCE_MAX_LEN = 40

#: 한 제안이 들고 다니는 근거 수 상한. 스키마와 같은 값이다.
_EVIDENCE_MAX_ITEMS = 4


def suggestion_evidence(evidence_json: str) -> list[str]:
    """제안의 근거 문구를 읽는다. 깨진 값이면 빈 목록이다. (#790)

    `draft_exercises` 와 같은 이유로 관대하다 — 근거 하나가 이상해서 제안 카드
    자체가 안 뜨면, 트레이너는 검토할 것이 있는지조차 알 수 없다.

    자동 후보의 근거는 코드다(#2301). 코드로 바꾸기 전에 문장으로 저장된 행은
    여기서 코드로 되돌려, 이미 쌓인 검토 대기 후보도 화면 언어로 표시되게 한다.
    """
    try:
        raw = json.loads(evidence_json) if evidence_json else []
    except json.JSONDecodeError:
        return []
    if not isinstance(raw, list):
        return []
    legacy = routine_suggestion_service.LEGACY_EVIDENCE_LABELS
    return [
        legacy.get(item.strip(), item.strip())[:_EVIDENCE_MAX_LEN]
        for item in raw[:_EVIDENCE_MAX_ITEMS]
        if isinstance(item, str) and item.strip()
    ]


def draft_exercises(exercises_json: str) -> list[ProgramDraftExercise]:
    """저장된 운동 목록을 읽는다. 깨진 항목이 목록 전체를 막지 않는다.

    스키마가 거른 값만 저장되지만, 손으로 고쳤거나 예전 형식이 남은 항목 하나
    때문에 초안을 아예 못 여는 편이 더 나쁘다 — 읽을 수 있는 항목만 돌려준다.
    """
    try:
        raw = json.loads(exercises_json) if exercises_json else []
    except json.JSONDecodeError:
        return []
    return _validated_exercises(raw)


def _validated_exercises(raw: object) -> list[ProgramDraftExercise]:
    if not isinstance(raw, list):
        return []
    out: list[ProgramDraftExercise] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        try:
            out.append(ProgramDraftExercise.model_validate(item))
        except ValidationError:
            continue
    return out


#: `TrainerSchedule.status` 에 저장되는 계약값. 화면 문구처럼 보이지만 DB 에 그대로
#: 들어가고 앱(`ScheduleStatus`)도 이 문자열로 거른다 — 번역하거나 표기 체계를
#: 갈아 끼우면 기존 행이 어느 질의에도 걸리지 않는다.
SCHEDULE_UPCOMING = "예정"


SCHEDULE_DONE = "완료"


SCHEDULE_CANCELLED = "취소"


SCHEDULE_NO_SHOW = "노쇼"


SCHEDULE_GAP = "공백"

#: 더 이상 진행 상태가 바뀌지 않는 상태들. 여기 들어간 세션은 수정·완료·재취소가
#: 막힌다 — 완료된 PT 를 나중에 취소로 바꾸거나 취소한 PT 를 완료로 되돌리면
#: 이미 파생된 기록(운동 기록·이행률)과 어긋난다. (#871)
SCHEDULE_TERMINAL = frozenset(
    {SCHEDULE_DONE, SCHEDULE_CANCELLED, SCHEDULE_NO_SHOW}
)


def _program_items(program_json: str) -> list[ProgramItem]:
    try:
        raw = json.loads(program_json) if program_json else []
    except json.JSONDecodeError:
        raw = []
    out: list[ProgramItem] = []
    for m in raw:
        if not isinstance(m, dict):
            continue
        out.append(ProgramItem(
            name=str(m.get("name", "") or "-"),
            # 세트·횟수·중량·시간은 예전에 자유 문자열로 저장됐다.
            # LooseInt/LooseFloat 가 "10회"·"20kg" 에서 숫자를 되짚어 준다
            # (#1276, #1310).
            sets=m.get("sets"),
            reps=m.get("reps"),
            hold_seconds=m.get("hold_seconds"),
            weight=m.get("weight"),
            duration=m.get("duration"),
            # 이 키가 없는 예전 행은 분 × 60 으로 채워진다(#2221).
            duration_seconds=m.get("duration_seconds"),
            date=m.get("date"),
            intensity=m.get("intensity") or "moderate",
            # 이 키가 없는 예전 행은 세션 구분 없는 목록으로 그대로 읽힌다(#709).
            session=str(m.get("session", "") or ""),
            # 이 키가 없는 예전 행은 기본값으로 읽힌다(#1233).
            type=m.get("type") or "근력",
        ))
    return out


def _amount_label(
    type_: str,
    *,
    minutes: int,
    sets: int | None,
    reps: int | None,
    weight: float | None,
    hold_seconds: int | None = None,
    duration_seconds: int | None = None,
) -> str:
    """운동 한 줄이 말하는 **양**. 근력은 세트·횟수·중량, 나머지는 시간이다.

    `_program_item_label` 과 같은 규칙이고(#1276), 프로그램이 아니라 배정 한 건을
    다루는 자리(알림 본문·배정 수행 이력)가 쓴다. 예전에는 그 두 곳이 유형과
    무관하게 `분` 으로 적어, 근력을 배정받은 회원의 알림이 `스쿼트 · 15분` 이라고
    말했다 — 무엇을 몇 번 하라는 것인지가 빠진 문장이다.

    근력인데 세트가 아예 없는 것은 이 칸이 생기기 전의 배정뿐이라, 그때만
    예전처럼 분으로 되돌아간다.

    유형은 두 어휘로 들어온다 — 트레이너 배정은 한글(`근력`), 회원 기록은 영문
    코드(`strength`)다. 한쪽만 보면 다른 쪽이 조용히 분으로 떨어지므로 정규화해서
    비교한다.

    시간은 초가 있으면 초까지 적는다 — `45초`·`1시간 30분`(#2546). 초 칸이
    생기기 전의 배정은 분 × 60 으로 읽어 예전과 같은 `N분` 이다.
    """
    if exercise_types.normalize(type_) != exercise_types.STRENGTH or sets is None:
        return format_duration(seconds_or_minutes(duration_seconds, minutes))
    parts = [f"{sets}세트"]
    # 버티는 운동은 초로 읽는다 — `플랭크 · 3세트 · 60초`. (#1969)
    if hold_seconds:
        parts.append(f"{hold_seconds}초")
    elif reps:
        parts.append(f"{reps}회")
    # 맨몸 운동(0)은 중량을 적지 않는다 — `_program_item_label` 과 같다. (#2533)
    if weight:
        parts.append(f"{weight:g}kg")
    return " · ".join(parts)


def _routine_notification_args(
    name: str,
    type_: str,
    *,
    minutes: int,
    sets: int | None,
    reps: int | None,
    weight: float | None,
    hold_seconds: int | None = None,
    duration_seconds: int | None = None,
) -> dict[str, Any]:
    """루틴 배정 알림의 틀 인자(#2302). 양은 [_amount_label] 과 같은 규칙으로 읽는다.

    문장 대신 값을 남긴다 — 회원이 영어 화면이면 `15 min`·`3 sets` 로 조립된다.
    근력인지는 여기서 정해 둔다. 유형이 두 어휘(`근력`·`strength`)로 들어오는데,
    읽는 쪽마다 정규화 규칙을 다시 갖게 하면 한쪽이 어긋난다.
    """
    return {
        "name": name,
        "strength": exercise_types.normalize(type_) == exercise_types.STRENGTH,
        "minutes": minutes,
        # 초까지의 시간(#2546). `minutes` 는 틀을 모르는 쪽을 위해 둔다.
        "seconds": seconds_or_minutes(duration_seconds, minutes),
        "sets": sets,
        "reps": reps,
        "hold_seconds": hold_seconds,
        "weight": weight,
    }


#: 담당이 끊긴 회원의 일정이 스케줄에 쓰는 이름(#2589).
DETACHED_CLIENT_NAME = "해제 회원"


def _schedule_out(
    s: TrainerSchedule,
    *,
    detached: bool = False,
    is_reservation: bool | None = None,
) -> ScheduleSessionOut:
    """일정 한 행을 응답으로. [detached] 면 회원 식별·기록 값을 가린다. (#2589)

    [is_reservation] 은 회원 예약이 이 일정을 소유하는가(#2756). 여러 행을
    한 번에 만드는 [_schedule_outs] 는 미리 모아 넘기고, 넘기지 않으면 한 번
    조회한다.

    담당이 끊긴 회원의 일정도 트레이너가 참여한 수업이라 스케줄에 남긴다. 다만
    회원 상세·식단·기록 차단(#2281)과 같은 경계로, 누구였는지와 그 수업에 적힌
    글·프로그램·취소 사유는 보여 주지 않는다. 언제·무슨 종류·어떻게 끝났는지만
    남는다.
    """
    if is_reservation is None:
        db = object_session(s)
        is_reservation = db is not None and _is_reservation_schedule(db, s.id)
    if detached:
        return ScheduleSessionOut(
            id=s.id, date=s.date, time=s.time,
            client_name=DETACHED_CLIENT_NAME, member_id=None,
            type=s.type, duration_minutes=s.duration_minutes, status=s.status,
            note="", program=[], program_sent=False,
            cancelled_at=s.cancelled_at,
            cancellation_source=s.cancellation_source,
            no_show_at=s.no_show_at,
            member_detached=True,
            is_reservation=is_reservation,
        )
    return ScheduleSessionOut(
        id=s.id, date=s.date, time=s.time, client_name=s.client_name,
        member_id=s.member_id, type=s.type, duration_minutes=s.duration_minutes, status=s.status,
        note=s.note, program=_program_items(s.program_json),
        program_sent=s.program_sent_at is not None,
        cancelled_at=s.cancelled_at,
        cancellation_source=s.cancellation_source,
        cancellation_reason=s.cancellation_reason,
        no_show_at=s.no_show_at,
        consultation=_schedule_consultation_out(s.consultation),
        is_reservation=is_reservation,
    )


def _schedule_consultation_out(
    c: ConsultationRequest | None,
) -> ScheduleConsultationOut | None:
    if c is None:
        return None
    return ScheduleConsultationOut(
        id=c.id,
        exercise_goal=c.exercise_goal,
        health_purpose_type=c.health_purpose_type,
        health_purpose_detail=c.health_purpose_detail,
        message=c.message,
    )


def _is_consultation_booking(s: TrainerSchedule) -> bool:
    """상담 요청을 수락해 생긴 상담 일정인가. (#2584)

    수락은 담당 연결이 아니라, 이 일정의 회원은 아직 연결 전일 수 있다. 회원이
    이 트레이너에게 직접 보낸 요청이라 인박스와 같은 범위로 연결 여부와 관계없이
    이름·요청 내용이 보이고, 메모 수정·완료가 된다 — 해제 회원 익명 처리(#2589)와
    해제 때 남은 일정 취소에서 빠진다.
    """
    return s.consultation_id is not None and s.type == "상담"


def _is_reservation_schedule(db: Session, session_id: str) -> bool:
    """Return whether a member reservation owns this schedule row."""
    return db.scalar(
        select(TrainerReservation.id)
        .where(TrainerReservation.schedule_id == session_id)
        .limit(1)
    ) is not None


def _clock_minutes(value: str) -> int:
    """`HH:MM` 을 자정부터의 분으로. 형식이 다르면 ValueError."""
    hour, minute = value.split(":")
    return int(hour) * 60 + int(minute)


def _retire_personal_routines(
    db: Session, trainer_id: str, member_id: str, *, today: date
) -> None:
    """이 트레이너가 이 회원에게 보내 둔 개인운동을 오늘부로 내린다. (#2224)

    새로 보낼 때마다 부른다. 내리지 않으면 PT 가 당겨진 주에 지난 개인운동과
    새 개인운동이 **함께** 걸려 회원이 두 배를 받는다 — 트레이너는 바꿔 준
    것으로 아는데 회원은 더해진 것을 본다.

    지우지 않고 `ended_on` 만 오늘로 찍는다 — 회원이 지난 날짜를 열면 그날
    걸려 있던 목록이 그대로 보여야 한다(#2161).

    [today] 는 **새 개인운동이 걸리기 시작하는 날**이다. `개인운동만` 을 미래
    시작일로 보내면(#2656) 이전 것은 그 전날까지 걸려 있다가 시작일에 교대한다
    — 그 사이 회원 목록이 비지 않는다. 시작일 뒤에야 걸리기로 했던 옛 것(앞서
    더 먼 시작일로 보낸 것)은 걸리기 전에 내린다: `ended_on` 을 그 첫날로 찍어
    하루도 뜨지 않게 한다(`ended_on >= active_from` 제약을 지킨다).

    **프로그램 세션 줄은 건드리지 않는다.** 개인운동만 `delivery_kind` 를 달고
    있어(#2223) 그 값으로 가른다 — PT 프로그램 배정은 비어 있다.
    """
    iso = today.isoformat()
    live = (
        TrainerRoutine.trainer_id == trainer_id,
        TrainerRoutine.member_id == member_id,
        TrainerRoutine.status == ROUTINE_APPROVED,
        TrainerRoutine.delivery_kind.is_not(None),
        or_(
            TrainerRoutine.ended_on.is_(None),
            TrainerRoutine.ended_on > iso,
        ),
    )
    db.execute(
        update(TrainerRoutine)
        .where(*live, TrainerRoutine.active_from <= iso)
        .values(ended_on=iso)
    )
    db.execute(
        update(TrainerRoutine)
        .where(*live, TrainerRoutine.active_from > iso)
        .values(ended_on=TrainerRoutine.active_from)
    )


def _release_cancelled_reservation(
    db: Session, s: TrainerSchedule, *, source: str | None = None
) -> bool:
    """취소된 일정에 걸린 회원 예약을 풀고 좌석을 돌려준다(커밋 없음). (#2283)

    취소 주체는 이번 취소의 [source] 를, 없으면 일정에 이미 적힌 값을 넘긴다 —
    트레이너 화면에서 고른 `회원 사정`·`트레이너 사정` 이 예약 정리에서도 같은
    뜻이다.

    reservation_service 가 이 모듈을 가져다 쓰므로 순환을 피해 함수 안에서 부른다.
    풀어 준 예약이 있으면 True.
    """
    from app.services import reservation_service

    released = reservation_service.release_for_cancelled_schedule(
        db, s.id, cancelled_by=source or s.cancellation_source or "trainer"
    )
    return bool(released)


def _active_link(db: Session, member_id: str) -> TrainerClient | None:
    """회원의 현재 담당(활성) 링크 — 가장 오래된 active 1건. 없으면 None.

    '현재 담당 코치 1명' 판정의 단일 소스. get_member_trainer_id / build_member_coach 등이
    각자 같은 쿼리를 중복하면 divergence 위험이 있어 여기로 모은다(리뷰 #281).
    """
    return db.scalar(
        select(TrainerClient)
        .where(TrainerClient.member_id == member_id, TrainerClient.active.is_(True))
        .order_by(TrainerClient.created_at)
        .limit(1)
    )


def get_member_trainer_id(db: Session, member_id: str) -> str | None:
    """회원의 현재 담당 트레이너 id. 활성(active) 링크만 인정하며 없으면 None.

    휴면(비활성) 링크는 '현재 담당'이 아니므로 제외한다(리뷰 재-#3) — 비활성 링크만
    가진 회원은 코치 조회/발신이 불가(404/빈 목록)해야 한다.
    """
    link = _active_link(db, member_id)
    return link.trainer_id if link is not None else None


@dataclass(frozen=True)
class RoutineDayItem:
    """그날 걸려 있던 추천 개인운동 하나와 그날 했는지. (#2161)"""

    routine_id: str
    name: str
    #: 유산소|근력|스트레칭|기타 — 배정의 한글 유형 그대로다.
    type: str
    minutes: int
    #: 목록 순서. 트레이너가 정한 차례이자 "다음 운동" 을 셀 때의 기준이다.
    sort_order: int
    #: ai|trainer
    source: str
    done: bool
    #: 그날 완료로 남긴 분. 하지 않았으면 None.
    completed_minutes: int | None
    #: 그날 완료를 **다음 날 이후에** 체크했는가(#2506 의 지난 날짜 체크). 완료로
    #: 세지만 트레이너는 "몰아서 체크했다" 를 따로 본다(#2508).
    late: bool = False
    #: 그날 완료로 남은 운동 기록 id. 트레이너 메모가 이 완료를 가리킨다(#2510).
    session_id: str | None = None
    #: 이 배정이 걸린 기간 — 회원 목록에 뜨는 첫날과 내려가는 날(그날은 안 뜬다).
    #: 트레이너가 배정 묶음을 그릴 때 쓴다(#2508).
    active_from: str = ""
    ended_on: str | None = None
    #: 개인운동(`delivery_kind` 를 단 줄)인가. 아니면 기한 없는 따로 배정이다.
    personal: bool = False


@dataclass(frozen=True)
class RoutineDay:
    """하루치 추천 개인운동 — 그날 목록(정렬순)과 그날 완료. (#2161)"""

    date: date
    routines: list[RoutineDayItem]


def _checked_after(session: ExerciseSession, day: date) -> bool:
    """[day] 의 완료를 그다음 날 이후에 체크했는가. (#2508)

    완료가 붙는 날은 회원이 고른 운동일이고(#2506), 체크한 때는 행이 생긴
    시각이다 — 둘을 KST 날짜로 견준다. 시각이 없는 옛 행은 제때 한 것으로 본다.
    """
    created = session.created_at
    if created is None:
        return False
    return clock.to_seoul(created).date() > day


def member_routine_days(
    db: Session,
    member_id: str,
    start: date,
    end: date,
    *,
    trainer_id: str | None = None,
    keep_done_on_end_day: bool = False,
) -> list[RoutineDay]:
    """[start]~[end](양끝 포함)의 날마다 걸려 있던 추천 개인운동과 그날 완료. (#2161)

    추천 개인운동은 매일 새로 체크하는 목록이라, 기간을 되짚는 쪽(운동 AI 맞춤
    조언, #2162)은 날마다 "무엇이 걸려 있었고 무엇을 했나" 를 읽어야 한다 — 완료
    기록만 세면 안 한 날이 보이지 않는다.

    회원 화면(`build_member_routines`)과 같은 규칙이다: 지금의 담당 기준(담당이
    없으면 AI 자동 추천), 승인된 것만, 그날 걸려 있던 것만. 목록이 빈 날도 한
    칸을 차지한다 — 날짜가 빠지면 부르는 쪽이 "안 걸린 날" 과 "없는 날" 을 가를
    수 없다. 아직 오지 않은 날은 담지 않는다. 하루치 AI 추천을 새로 만들지 않는다
    — 읽기만 한다.

    쿼리는 기간 길이와 무관하게 둘이다(배정, 완료).

    [trainer_id] 를 주면 그 트레이너의 배정만 읽는다 — 트레이너 리포트(#2772)
    가 자기가 보낸 배정으로 분모를 세는 자리다. 생략하면 지금의 담당이다.

    [keep_done_on_end_day] 를 켜면 **내려간 날에 이미 한** 배정도 그날 칸에
    남긴다(#2508). 새 개인운동이 오면 옛 것은 그날부로 내려가는데(#2224), 회원이
    그 전에 옛 것을 체크했다면 그 완료는 그날의 이행이다 — 빼면 한 일이 사라지고,
    분모에서만 빼면 완료가 분모보다 많아진다. 하지 않은 옛 것은 그날 칸에 두지
    않는다(회원 화면에도 없던 것이다).
    """
    end = min(end, clock.today())
    if end < start:
        return []
    if trainer_id is None:
        trainer_id = get_member_trainer_id(db, member_id)
    start_iso, end_iso = start.isoformat(), end.isoformat()
    rows = db.scalars(
        select(TrainerRoutine)
        .where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id == member_id,
            TrainerRoutine.status == ROUTINE_APPROVED,
            # 기간과 겹치는 배정만 — 기간 안 어느 날이든 걸려 있었던 것.
            TrainerRoutine.active_from <= end_iso,
            or_(
                TrainerRoutine.ended_on.is_(None),
                (
                    TrainerRoutine.ended_on >= start_iso
                    if keep_done_on_end_day
                    else TrainerRoutine.ended_on > start_iso
                ),
            ),
        )
        .order_by(TrainerRoutine.sort_order, TrainerRoutine.created_at)
    ).all()
    done: dict[tuple[str, date], ExerciseSession] = {}
    if rows:
        for session in db.scalars(
            select(ExerciseSession).where(
                ExerciseSession.assigned_routine_id.in_([r.id for r in rows]),
                ExerciseSession.week_start
                >= exercise_service.monday_of_str(start_iso),
                ExerciseSession.week_start <= end_iso,
            )
        ).all():
            day = exercise_activity.activity_date_of(session)
            if day is not None and start <= day <= end:
                done[(session.assigned_routine_id, day)] = session

    days: list[RoutineDay] = []
    day = start
    while day <= end:
        days.append(
            RoutineDay(
                date=day,
                routines=_routine_items_on(
                    rows, done, day, keep_done_on_end_day=keep_done_on_end_day
                ),
            )
        )
        day += timedelta(days=1)
    return days


def _routine_items_on(
    rows: Sequence[TrainerRoutine],
    done: dict[tuple[str, date], ExerciseSession],
    day: date,
    *,
    keep_done_on_end_day: bool,
) -> list[RoutineDayItem]:
    """[day] 에 걸려 있던 배정과 그날 완료 — [member_routine_days] 의 하루치.

    로스터 이행률(#2513)이 여러 회원을 한 번에 읽고 같은 규칙으로 세려고 따로
    둔다. [rows] 는 배정 순서로 정렬돼 있어야 한다.
    """
    iso = day.isoformat()
    items: list[RoutineDayItem] = []
    for row in rows:
        completion = done.get((row.id, day))
        if row.active_from > iso:
            continue
        if row.ended_on is not None and row.ended_on <= iso:
            # 내려간 날에 이미 한 것만 그날 칸에 남는다([member_routine_days]).
            if not (
                keep_done_on_end_day
                and row.ended_on == iso
                and completion is not None
            ):
                continue
        items.append(
            RoutineDayItem(
                routine_id=row.id,
                name=row.name,
                type=row.type,
                minutes=row.minutes,
                sort_order=row.sort_order,
                source=row.source,
                done=completion is not None,
                completed_minutes=(
                    completion.minutes if completion is not None else None
                ),
                late=(
                    completion is not None and _checked_after(completion, day)
                ),
                session_id=completion.id if completion is not None else None,
                active_from=row.active_from,
                ended_on=row.ended_on,
                personal=row.delivery_kind is not None,
            )
        )
    return items


def routine_sent_on(row: TrainerRoutine) -> date:
    """배정을 **보낸 날**(KST). (#2656)

    대개 회원 목록에 걸린 첫날(`active_from`)과 같다 — PT 에 붙여 두었다가
    보낸 개인운동도 보낸 날부터 건다(#2224). `개인운동만` 은 시작일을 미래로
    고르면 그날부터 걸리므로, 보낸 날은 행을 만든 날이다.
    """
    if row.delivery_kind == DELIVERY_ROUTINE_ONLY and row.created_at is not None:
        created = clock.to_seoul(row.created_at).date()
        return min(created, date.fromisoformat(row.active_from))
    return date.fromisoformat(row.active_from)


class RoutineDayInFuture(Exception):
    """아직 오지 않은 날의 개인운동 목록을 물었다. (#2161)"""


def _done_pt_numbers(db: Session, member_id: str, trainer_id: str) -> dict[str, int]:
    """이 회원이 이 트레이너와 마친 PT 의 회차 — 세션 id → 1부터의 순번. (#2697)

    회원 일정 응답(`member_mirror`)과 PT 완료 알림(`schedule`, #3027)이 같은 번호를 쓴다.

    목록은 최근 100건만 내리지만 회차는 처음부터 센다. 상담은 수업이 아니라 세지
    않는다. 같은 날·같은 시각이면 id 로 순서를 고정해 응답마다 번호가 바뀌지 않게 한다.
    """
    ids = db.scalars(
        select(TrainerSchedule.id)
        .where(
            TrainerSchedule.member_id == member_id,
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.status == SCHEDULE_DONE,
            TrainerSchedule.type != "상담",
        )
        .order_by(
            TrainerSchedule.date.asc(),
            TrainerSchedule.time.asc(),
            TrainerSchedule.id.asc(),
        )
    ).all()
    return {sid: i for i, sid in enumerate(ids, start=1)}
