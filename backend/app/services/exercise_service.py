"""
운동 주간 집계 서비스 — 프론트 _exerciseCurrentWeek 로직을 그대로 재현.

핵심 규칙(프론트와 동일):
- 요일 라벨: 월~일 (월=index 0)
- 타입 버킷: 유산소 / 근력 / 스트레칭 / 기타 네 가지(app.services.exercise_types).
  옛 값(walking·yoga·stretching)은 읽는 자리에서 접어 준다.
- date_label: 오늘/어제/MM월 DD일/N요일 (요일 라벨 → 날짜 환산)
- time_label, items: 타입별 기본값 합성 (drift 스키마에 없는 표시용 데이터)
- streak: 운동한 요일 중 가장 긴 연속 구간의 길이 ("N일 연속"). 활성 일수의 단순
  합계가 아니다 — 월·수·금 운동은 3일이 아니라 1일 연속. 프론트의
  `longestActiveStreak` 와 같은 정의.
- sessions 정렬: 최근 요일 먼저
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import ExerciseSession
from app.services import exercise_activity, exercise_types, period_window
from app.services.exercise_catalog import energy, resolver

#: 요일 라벨(월=0 … 일=6). 순서를 두 벌 두지 않으려고 논리 운동일 모듈의 정의를
#: 그대로 쓴다 — 여기서 한 칸이라도 어긋나면 같은 기록이 화면과 AI 에서 다른
#: 날짜가 된다. (#1264)
WEEKDAY_LABELS = list(exercise_activity.WEEKDAY_LABELS)

#: 근력 1세트가 차지하는 벽시계 시간(세트 + 휴식). 회원 앱
#: `kStrengthMinutesPerSetWithRest` 와 같은 값이다 — 세트를 모르는 옛 기록을
#: 세트로 되짚을 때만 쓴다. (#1262)
STRENGTH_MINUTES_PER_SET = 3.0


def sets_of(row) -> int:
    """근력 기록의 세트 수. 적혀 있으면 그 값, 없으면 분에서 환산한 값."""
    recorded = getattr(row, "sets", None)
    if recorded:
        return int(recorded)
    return round(row.minutes / STRENGTH_MINUTES_PER_SET)


def session_date_of(row) -> date | None:
    """기록의 실제 날짜. 저장은 (주 시작 + 요일 라벨)로 쪼개져 있다. (#1276)

    요일만으로는 몇 주 전 기록과 이번 주 기록이 구분되지 않는다 — 앱이 수정
    시트를 열 때 원래 날짜를 되살리려면 여기서 되돌려야 한다.

    계산은 [exercise_activity.activity_date_of] 하나뿐이다(#1264). 예전에는 같은
    환산을 여기서 한 벌 더 갖고 있었고, 그쪽만 깨진 옛 행에서 빈 칸을 냈다 —
    화면은 날짜 없는 기록을, AI 는 폴백으로 되살린 날짜를 보는 상태였다. 셋 중
    어느 것으로도 알 수 없을 때만 None 이다: 지어낸 날짜보다 빈 칸이 낫다.
    """
    return exercise_activity.activity_date_of(row)


def monday_of_this_week_str() -> str:
    today = clock.today()
    return (today - timedelta(days=today.weekday())).isoformat()


def monday_of_str(day: str) -> str:
    """`day`(YYYY-MM-DD) 가 속한 주의 월요일.

    지난 주 세션을 오늘 완료 처리할 수 있으므로, 파생 기록의 주차는 완료 시점이
    아니라 **세션 날짜** 기준이어야 한다. 형식이 깨진 값은 이번 주로 떨어뜨린다.
    """
    try:
        d = date.fromisoformat(day)
    except (TypeError, ValueError):
        return monday_of_this_week_str()
    return (d - timedelta(days=d.weekday())).isoformat()


def weekday_label_of(day: str) -> str:
    """`day`(YYYY-MM-DD) 의 요일 라벨(월~일). 형식이 깨지면 오늘 요일."""
    try:
        d = date.fromisoformat(day)
    except (TypeError, ValueError):
        return WEEKDAY_LABELS[clock.today().weekday()]
    return WEEKDAY_LABELS[d.weekday()]


def estimate_calories(type_: str, minutes: int, intensity: str) -> int:
    """유형·분·강도만으로 추정하는 **폴백**. 운동 이름도 체중도 안 볼 때다.

    이름이 있으면 [estimate] 를 쓴다 — 이 함수는 같은 `유산소 30분` 이면 달리기든
    자전거든, 회원 체중이 몇이든 같은 값을 낸다(#1312). 그래도 남겨 둔 이유는
    이름이 종목표에 붙지 않는 기록이 늘 있기 때문이고, 그때 화면마다 값이
    갈리지 않으려면 폴백도 한 곳이어야 하기 때문이다(#1131).

    운동 유형은 정규화해서 본다 — 옛 값(`walking`·`yoga`)으로 저장된 기록도
    같은 표를 타야 회원 화면에서 칼로리가 갈리지 않는다.
    """
    return energy.fallback(type_, minutes, intensity).calories


def member_weight_kg(db: Session, user_id: str) -> float | None:
    """소모 칼로리 계산에 쓸 회원 체중. 건강 프로필에 없으면 None.

    없으면 지어내지 않는다 — 기준 체중으로 계산한 값은 이 회원의 값이 아니고,
    그것을 참조표 근거(`db`)로 표시하면 실제보다 높은 신뢰 신호를 준다.
    """
    from app.models.models import HealthProfile

    return db.scalar(
        select(HealthProfile.weight_kg).where(HealthProfile.user_id == user_id)
    )


def estimate(
    db: Session,
    *,
    name: str,
    type_: str,
    minutes: int,
    intensity: str,
    weight_kg: float | None,
    use_ai: bool = True,
) -> energy.Estimate:
    """운동 이름·체중까지 반영한 소모 칼로리와 그 근거. (#1312)

    이름이 종목표에 붙고 체중을 알면 참조표 계수로, 아니면 유형 평균으로
    떨어진다. 어느 쪽이든 값과 함께 `source` 가 나오므로 화면이 확정값과
    어림값을 구분해 보여 줄 수 있다.

    이름이 비어 있으면 부르지 않아도 된다 — 불러도 폴백이 나오지만, 이름이
    없는 동안에는 화면이 숫자를 띄우지 않는 것이 이 이슈의 요구다.
    """
    resolution = resolver.resolve(db, name, use_ai=use_ai)
    return energy.estimate(
        resolution.row,
        type_,
        minutes,
        intensity,
        weight_kg,
        resolver=resolution.resolver,
        confidence=resolution.confidence,
    )


def _date_label_for_day(day_label: str) -> str:
    today = clock.today()
    today_idx = today.weekday()  # 0=월
    if day_label not in WEEKDAY_LABELS:
        return day_label
    day_idx = WEEKDAY_LABELS.index(day_label)
    delta = today_idx - day_idx
    if delta == 0:
        return "오늘"
    if delta == 1:
        return "어제"
    if 1 < delta <= 6:
        d = today - timedelta(days=delta)
        return f"{d.month}월 {d.day}일"
    return f"{day_label}요일"


def _default_time_label(t: str) -> str:
    return {
        exercise_types.CARDIO: "07:30",
        exercise_types.STRENGTH: "18:00",
        exercise_types.STRETCHING: "20:00",
    }.get(exercise_types.normalize(t), "15:00")


def _default_items(t: str) -> list[str]:
    return {
        exercise_types.CARDIO: ["러닝머신 30분"],
        exercise_types.STRENGTH: ["스쿼트 3세트", "데드리프트 3세트"],
        exercise_types.STRETCHING: ["전신 스트레칭 20분"],
    }.get(exercise_types.normalize(t), [])


def _bucket(t: str) -> str:
    """집계 축. 기타는 유산소가 아니라 자기 칸으로 간다 (#996)."""
    return exercise_types.normalize(t)


#: 프로필에 목표가 없을 때 쓰는 기본값. 회원 앱의 `UserProfile` 기본값과 같다 —
#: 두 앱이 다른 기본값을 쓰면 같은 회원의 그래프에 다른 목표선이 그려진다.
DEFAULT_WEEKLY_MINUTES_GOAL = 150
DEFAULT_WEEKLY_BURN_GOAL = 500


def weekly_goals(profile) -> tuple[int, int]:
    """(주간 운동 시간 목표, 주간 소모 칼로리 목표). 프로필이 없으면 기본값."""
    minutes = getattr(profile, "weekly_exercise_minutes_goal", None)
    calories = getattr(profile, "weekly_burn_goal", None)
    return (
        minutes if minutes and minutes > 0 else DEFAULT_WEEKLY_MINUTES_GOAL,
        calories if calories and calories > 0 else DEFAULT_WEEKLY_BURN_GOAL,
    )


def _longest_streak(daily: list[int]) -> int:
    """'N일 연속' — 운동한 요일 중 가장 긴 연속 구간의 길이.

    활성 일수의 단순 합계가 아니다: 월·수·금 운동은 3일이 아니라 1일 연속.
    프론트 `longestActiveStreak` / LocalApiInterceptor 와 같은 정의.
    """
    best = run = 0
    for m in daily:
        run = run + 1 if m > 0 else 0
        best = max(best, run)
    return best


def build_current_week(rows: list) -> dict:
    """ExerciseSession row 리스트 → 프론트 계약 형태의 dict."""
    per_day = {l: 0 for l in WEEKDAY_LABELS}
    per_day_cal = {l: 0 for l in WEEKDAY_LABELS}
    per_cardio = {l: 0 for l in WEEKDAY_LABELS}
    per_strength = {l: 0 for l in WEEKDAY_LABELS}
    per_stretch = {l: 0 for l in WEEKDAY_LABELS}
    per_other = {l: 0 for l in WEEKDAY_LABELS}
    per_sets = {l: 0 for l in WEEKDAY_LABELS}
    total_minutes = 0
    total_calories = 0
    sessions = []

    for r in rows:
        total_minutes += r.minutes
        total_calories += r.calories
        per_day[r.day_label] = per_day.get(r.day_label, 0) + r.minutes
        per_day_cal[r.day_label] = per_day_cal.get(r.day_label, 0) + r.calories
        bucket_map = {
            exercise_types.CARDIO: per_cardio,
            exercise_types.STRENGTH: per_strength,
            exercise_types.STRETCHING: per_stretch,
            exercise_types.OTHER: per_other,
        }
        bucket = _bucket(r.type)
        target = bucket_map[bucket]
        target[r.day_label] = target.get(r.day_label, 0) + r.minutes
        if bucket == exercise_types.STRENGTH:
            per_sets[r.day_label] = per_sets.get(r.day_label, 0) + sets_of(r)
        sessions.append({
            "id": r.id, "day_label": r.day_label, "type": r.type,
            "date": session_date_of(r),
            "name": getattr(r, "name", "") or "",
            "minutes": r.minutes,
            "sets": getattr(r, "sets", None),
            "reps": getattr(r, "reps", None),
            "weight": getattr(r, "weight", None),
            "calories": r.calories,
            "calorie_source": getattr(r, "calorie_source", "") or "estimate",
            "intensity": getattr(r, "intensity", "moderate") or "moderate",
            "source": getattr(r, "source", "member") or "member",
            "assigned_routine_id": getattr(r, "assigned_routine_id", None),
            "assigned_routine_name": getattr(r, "assigned_routine_name", "") or "",
            # 개인 운동 회원 피드백은 없앴다(#1825). 응답 모양만 남긴다.
            "member_note": "",
            "trainer_feedback": getattr(r, "trainer_feedback", "") or "",
            "completed_at": getattr(r, "completed_at", None),
            "date_label": _date_label_for_day(r.day_label),
            "time_label": _default_time_label(r.type),
            # 회원이 적은 이름이 있으면 그게 이 기록의 내용이다. 없을 때만
            # 유형별 기본 문구로 채운다 — 이름 칸이 생기기 전 기록들이다. (#1276)
            "items": (
                [getattr(r, "assigned_routine_name", "")]
                if getattr(r, "assigned_routine_name", "")
                else [r.name] if getattr(r, "name", "")
                else _default_items(r.type)
            ),
        })

    # 최근 요일 먼저
    sessions.sort(key=lambda s: WEEKDAY_LABELS.index(s["day_label"]), reverse=True)

    daily = [per_day[l] for l in WEEKDAY_LABELS]
    streak = _longest_streak(daily)

    msg = (
        "주간 운동 목표 80%를 달성했어요! 오늘 가볍게 걷기를 더해 100%를 채워봐요."
        if total_minutes >= 240
        else "이번 주는 운동량이 조금 부족해요. 가벼운 산책부터 다시 시작해 봐요."
    )

    return {
        "sessions": sessions,
        "daily_minutes": daily,
        "daily_calories": [per_day_cal[l] for l in WEEKDAY_LABELS],
        "cardio_minutes": [per_cardio[l] for l in WEEKDAY_LABELS],
        "strength_minutes": [per_strength[l] for l in WEEKDAY_LABELS],
        "strength_sets": [per_sets[l] for l in WEEKDAY_LABELS],
        "stretching_minutes": [per_stretch[l] for l in WEEKDAY_LABELS],
        "other_minutes": [per_other[l] for l in WEEKDAY_LABELS],
        # 옛 이름. 아직 이 필드를 읽는 클라이언트가 있어 같은 값을 함께 내려준다.
        # 두 앱이 stretching_minutes 로 옮긴 뒤에 지운다. (#1276)
        "flexibility_minutes": [per_stretch[l] for l in WEEKDAY_LABELS],
        "day_labels": WEEKDAY_LABELS,
        "total_minutes": total_minutes,
        "total_calories": total_calories,
        "streak_days": streak,
        "ai_coach_message": msg,
    }


# --- 기간별 운동 조언 (#1025) -------------------------------------------------
#
# 식단이 먼저 한 것(#1017)과 같은 규칙이다. 기간을 바꾸는 것은 "무엇을 볼지" 를
# 바꾸는 일인데, 그래프만 갈리고 조언이 오늘 이야기로 남으면 이번 주를 보면서
# "오늘은 유산소를 했네요" 를 읽게 된다.
#
# 없는 기록으로 조언을 지어내지 않는다 — 기록이 없으면 없다고 말한다.


@dataclass(frozen=True)
class ExerciseDayTotals:
    """하루치 운동 합계. **기록이 있는 날만** 만들어진다."""

    date: date
    minutes: int
    calories: int
    #: 유형별 시간(분). 키는 `exercise_types` 의 네 가지다.
    by_type: dict[str, int]

    @property
    def main_type(self) -> str:
        """그날 가장 오래 한 유형. 같으면 유산소 → 근력 → 스트레칭 → 기타 순."""
        order = [
            exercise_types.CARDIO,
            exercise_types.STRENGTH,
            exercise_types.STRETCHING,
            exercise_types.OTHER,
        ]
        return max(order, key=lambda t: (self.by_type.get(t, 0), -order.index(t)))


def daily_totals(rows: list, start: str, end: str) -> list[ExerciseDayTotals]:
    """[start, end] 구간의 기록 있는 날만 날짜순으로. (#1025)

    기록이 없는 날을 0 으로 채우지 않는다 — 쉰 날과 적지 않은 날은 다른 말이고,
    평균이 그 차이를 삼키면 조언이 사실과 어긋난다.
    """
    per_day: dict[date, dict] = {}
    for row in rows:
        # 구간 판정의 날짜도 화면과 같은 규칙이다 — 여기만 따로 세면 코치의
        # '최근 N일' 이 회원이 보는 기록과 다른 날을 가리킨다. (#1264)
        when = exercise_activity.activity_date_of(row)
        if when is None or not (start <= when.isoformat() <= end):
            continue
        bucket = per_day.setdefault(
            when, {"minutes": 0, "calories": 0, "by_type": {}}
        )
        bucket["minutes"] += row.minutes or 0
        bucket["calories"] += row.calories or 0
        kind = exercise_types.normalize(row.type)
        bucket["by_type"][kind] = bucket["by_type"].get(kind, 0) + (row.minutes or 0)
    return [
        ExerciseDayTotals(
            date=when,
            minutes=v["minutes"],
            calories=v["calories"],
            by_type=v["by_type"],
        )
        for when, v in sorted(per_day.items())
    ]


def _avg(values: list[int]) -> float:
    return sum(values) / len(values) if values else 0


def period_coach_message(days: list[ExerciseDayTotals], period: str) -> str:
    """기간에 맞는 운동 조언. (#1025, #1574)

    기간마다 **재료가 다르다.** 오늘은 오늘 한 운동, 이번 주는 며칠 움직였고
    무엇에 치우쳤는지, 전체는 최근 4주와 그 이전의 추세다. 말투도 다르다 —
    오늘은 다음 한 걸음을 제안하고, 이번 주·전체는 되짚어 준다.

    **한 문장 반을 넘기지 않는다.** 카드가 회원 앱·트레이너웹 양쪽에서 좁은 폭에
    들어가고, 길어질수록 정작 숫자가 묻힌다 — 짚어 주는 수치 하나와 다음 행동
    하나면 충분하다. (#1574)
    """
    if not days:
        if period == period_window.PERIOD_WEEK:
            return "이번 주 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?"
        if period == period_window.PERIOD_ALL:
            return "기록이 쌓이면 운동량과 유형의 흐름을 짚어 드릴게요."
        return "오늘 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?"

    if period == period_window.PERIOD_TODAY:
        today = days[-1]
        label = exercise_types.label_for(today.main_type)
        return (
            f"오늘 {label} 위주로 {today.minutes}분, {today.calories}kcal 썼어요. "
            "스트레칭으로 마무리해요."
        )

    total_minutes = sum(d.minutes for d in days)
    active_days = len(days)

    if period == period_window.PERIOD_WEEK:
        if active_days <= 1:
            return f"이번 주는 {total_minutes}분 하루뿐이에요. 한 번 더 나가면 흐름이 이어져요."
        # 한 유형에 쏠렸는지 — 코칭에서 가장 먼저 짚는 지점이다.
        by_type: dict[str, int] = {}
        for d in days:
            for kind, minutes in d.by_type.items():
                by_type[kind] = by_type.get(kind, 0) + minutes
        top = max(by_type, key=lambda k: by_type[k]) if by_type else None
        if top is not None and total_minutes and by_type[top] / total_minutes >= 0.8:
            missing = (
                exercise_types.STRENGTH
                if top == exercise_types.CARDIO
                else exercise_types.CARDIO
            )
            return (
                f"이번 주 {active_days}일 {total_minutes}분이 "
                f"{exercise_types.label_for(top)}에 몰렸어요. "
                f"{exercise_types.label_for(missing)}도 섞어 볼까요?"
            )
        return f"이번 주 {active_days}일 {total_minutes}분, 유형도 고르게 섞였어요."

    # 전체 — 최근 4주와 그 이전을 견준다. "나아지는 중인가" 가 이 화면의 질문이다.
    recent_from = days[-1].date - timedelta(days=27)
    recent = [d.minutes for d in days if d.date >= recent_from]
    earlier = [d.minutes for d in days if d.date < recent_from]
    if earlier and recent:
        if _avg(recent) > _avg(earlier) * 1.1:
            return "최근 4주 운동량이 그 전보다 늘었어요. 지금 방식이 잘 맞아요."
        if _avg(recent) < _avg(earlier) * 0.9:
            return "최근 4주 운동량이 줄고 있어요. 짧게라도 주 3일을 지켜 봐요."
    weeks = round(period_window.ALL_PERIOD_DAYS / 7)
    return f"{weeks}주 동안 {active_days}일 {total_minutes}분, 기복 없이 이어가고 있어요."


def period_days(
    db: Session, user_id: str, period: str
) -> tuple[str, str, list[ExerciseDayTotals]]:
    """기간 이름 → (시작, 끝, 그 구간의 하루별 합계). (#1574)

    운동 기록은 날짜가 아니라 (그 주 월요일, 요일) 로 저장되므로, 구간이 걸치는
    주를 모두 읽어 온 뒤 실제 날짜로 되돌려 거른다. 회원 앱과 트레이너웹이 이
    함수 하나를 함께 쓴다 — 조회 규칙이 갈리면 같은 회원의 `이번 주` 를 두 화면이
    다른 날부터 세게 된다.
    """
    start, end = period_window.period_bounds(period)
    weeks = exercise_activity.week_starts_covering(
        date.fromisoformat(start), date.fromisoformat(end)
    )
    rows = db.scalars(
        select(ExerciseSession).where(
            ExerciseSession.user_id == user_id,
            ExerciseSession.week_start.in_(weeks),
        )
    ).all()
    return start, end, daily_totals(list(rows), start, end)
