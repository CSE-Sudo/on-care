"""트레이너 회원 목록의 PT 관리 신호. (#2203)

회원 목록 배지는 "누가 흐름이 끊겼나, 누가 목표에서 벗어났나, 누가 불편을
호소하나" 에 답한다. 예전 배지(나트륨·당류 초과, 이행률 저조)는 트레이너 웹이
로스터의 오늘 영양소로 직접 셌는데, 나트륨·당류는 폐기된 만성질환 타깃의 기준이고
하루 값만 봐서 같은 회원이 날마다 배지를 달았다 뗐다 했다.

**기준은 이 모듈 한 곳에 있다.** 칼로리 이탈 ±15% 는 주간 리포트 요약
(`trainer_report_summary_service`)도 같은 상수를 가져다 쓴다 — 목록 배지와 리포트가
같은 회원을 서로 다른 기준으로 말하지 않게 한다.

저장하지 않고 로스터를 만들 때마다 계산한다. 쿼리 수는 회원 수와 무관한 상수이고,
각 쿼리는 필요한 창(최근 30일·이번 주·최근 7일)만 읽는다.

답장 대기는 여기 없다. 안 읽은 메시지 수는 트레이너 웹이 실시간으로 받는 값이라,
로스터를 받은 시점의 값으로 굳히면 답장한 뒤에도 배지가 남는다.
"""
from __future__ import annotations

from collections import defaultdict
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import date, timedelta

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import (
    AiConversation,
    AiMessage,
    ChatMessage,
    DietEntry,
    ExerciseSession,
    HealthProfile,
    TrainerClient,
    TrainerRoutine,
    TrainerSchedule,
)
from app.schemas.trainer_api import ClientSignalOut
from app.services import exercise_activity, exercise_service, exercise_types, health_focus
from app.services.coach import insights

# ---- 신호 종류 — 앱이 이 문자열로 배지·필터를 고른다. 번역하지 않는다. ----

SIGNAL_DISCOMFORT = "discomfort"
SIGNAL_RECORD_GAP = "record_gap"
SIGNAL_NO_SHOW = "no_show"
SIGNAL_ROUTINE_MISSED = "routine_missed"
SIGNAL_EXERCISE_GOAL_LOW = "exercise_goal_low"
SIGNAL_CALORIE_OFF = "calorie_off"
SIGNAL_PROTEIN_LOW = "protein_low"

#: 급한 순서. 응답의 `signals` 가 이 순서로 나가고, 목록은 앞의 것부터 보여 준다.
#: 몸이 아프다는 말이 가장 먼저고, 흐름이 끊긴 것(기록·출석)이 목표 이탈보다 앞선다.
SIGNAL_ORDER: tuple[str, ...] = (
    SIGNAL_DISCOMFORT,
    SIGNAL_RECORD_GAP,
    SIGNAL_NO_SHOW,
    SIGNAL_ROUTINE_MISSED,
    SIGNAL_EXERCISE_GOAL_LOW,
    SIGNAL_CALORIE_OFF,
    SIGNAL_PROTEIN_LOW,
)

#: 기록에서 나오는 신호. 기록이 끊긴 회원에게는 이것들을 내리지 않는다 — 기록이
#: 없으면 운동도 칼로리도 자동으로 '미달' 이 되어, 원인 하나를 배지 넷으로 말한다.
_RECORD_DERIVED = frozenset({
    SIGNAL_ROUTINE_MISSED,
    SIGNAL_EXERCISE_GOAL_LOW,
    SIGNAL_CALORIE_OFF,
    SIGNAL_PROTEIN_LOW,
})

# ---- 기준값 ----

#: 담당을 맺은 지 이 날 수가 안 된 회원은 통증·불편만 본다. 첫날부터 "기록 끊김·
#: 목표 미달" 이 뜨면 트레이너가 배지를 무시하는 법부터 배운다.
NEW_LINK_GRACE_DAYS = 3

#: 통증·불편을 찾는 기간(메시지 작성 시각 기준).
DISCOMFORT_WINDOW_DAYS = 7

#: 마지막 식단·운동 기록(없으면 담당 시작일)에서 오늘까지 이만큼 지나면 기록 끊김.
#: 3 이면 그끄제가 마지막 기록이고 그제·어제·오늘이 비어 있다.
RECORD_GAP_DAYS = 3
#: 기록을 찾아보는 가장 먼 날. 이보다 오래 비었으면 `days` 는 이 값에서 멈춘다 —
#: "30일 넘게" 로 읽는다.
RECORD_LOOKBACK_DAYS = 30

#: 노쇼와 회원 사정 취소를 이 기간에 이 횟수 이상이면 반복으로 본다. 트레이너
#: 사정 취소는 세지 않는다 — 회원의 미이행이 아니다(#871).
NO_SHOW_WINDOW_DAYS = 30
NO_SHOW_MIN_COUNT = 2
#: `TrainerSchedule.status`·`cancellation_source` 계약값.
#: `trainer_service.SCHEDULE_NO_SHOW`·`SCHEDULE_CANCELLED` 와 같다(테스트가 지킨다).
_SCHEDULE_NO_SHOW = "노쇼"
_SCHEDULE_CANCELLED = "취소"
_CANCELLED_BY_MEMBER = "member"

#: 배정 루틴·칼로리·단백질이 보는 창 — 어제까지 최근 이만큼. 오늘은 아직 끼니와
#: 운동이 진행 중이라 넣지 않는다.
RECENT_WINDOW_DAYS = 3
#: 배정 루틴이 이 날 수 이상 걸려 있었어야 미수행을 말한다. 어제 막 배정한 루틴을
#: 하루 안 했다고 배지를 달지 않는다.
ROUTINE_MIN_ASSIGNED_DAYS = 2
#: 칼로리·단백질 평균을 내려면 창 안에 기록한 날이 이만큼 있어야 한다. 하루 값은
#: 그날 사정이 크다.
MIN_RECORDED_DAYS = 2

#: 이번 주 유형별 달성률(경과일 비례) 평균이 이 아래면 운동 목표 미달.
EXERCISE_GOAL_LOW_PERCENT = 50
#: 주의 이 요일(월=0)부터 판단한다. 월·화는 쌓인 날이 적어 하루 쉰 것이 곧 미달이
#: 된다.
EXERCISE_GOAL_FROM_WEEKDAY = 2
#: 프로필에 유형별 목표가 없을 때의 기본값. 회원 앱 `kDefaultExerciseLoadGoals`
#: 와 같아야 한다 — 회원이 보는 링과 트레이너 배지가 다른 목표를 쓰면 안 된다.
DEFAULT_WEEKLY_CARDIO_MINUTES = 150
DEFAULT_WEEKLY_STRENGTH_SETS = 21
DEFAULT_WEEKLY_STRETCHING_MINUTES = 60

#: 칼로리 목표 기본값. 개인 목표(`HealthProfile.daily_calories`)가 먼저다.
DEFAULT_CALORIE_TARGET_KCAL = 2000
#: 칼로리가 목표에서 이만큼 벗어나면 이탈로 본다(과다·부족 모두). 하루하루가
#: 목표에 딱 맞는 주는 없으므로 좁게 잡으면 늘 뜬다. 리포트 요약도 이 값을 쓴다.
CALORIE_TOLERANCE = 0.15

#: 단백질 부족을 보는 건강 목표. 근력 향상은 단백질이 모자라면 운동한 만큼 근육이
#: 붙지 않고, 체중 감량은 열량을 줄이는 동안 근육부터 빠진다.
PROTEIN_FOCUS = frozenset({health_focus.FOCUS_STRENGTH, health_focus.FOCUS_WEIGHT_LOSS})
#: 개인 단백질 목표의 이 비율에 못 미치면 부족. 리포트의 탄단지 ±25% 와 같은 폭이다.
PROTEIN_LOW_RATIO = 0.75


def calorie_gap(mean_kcal: float, target_kcal: float) -> float:
    """목표 대비 벗어난 비율. 양수면 과다, 음수면 부족."""
    return (mean_kcal - target_kcal) / target_kcal


def calorie_off_target(mean_kcal: float, target_kcal: float) -> bool:
    """[CALORIE_TOLERANCE] 를 넘게 벗어났는가 — 목록 배지와 리포트가 함께 쓴다."""
    return abs(calorie_gap(mean_kcal, target_kcal)) > CALORIE_TOLERANCE


@dataclass
class _MemberData:
    diet_by_date: dict[str, tuple[int, float]]
    exercise_dates: set[date]
    week_sessions: list[ExerciseSession]
    discomfort: bool = False
    no_show_count: int = 0


def _positive(value: int | None, fallback: int) -> int:
    return value if value and value > 0 else fallback


def _record_gap_days(
    data: _MemberData, link_start: date, today: date
) -> int:
    """마지막 기록(없으면 담당 시작일)에서 오늘까지 지난 날 수. [RECORD_LOOKBACK_DAYS] 에서 멈춘다."""
    recorded = {date.fromisoformat(d) for d, (kcal, _) in data.diet_by_date.items() if kcal > 0}
    recorded |= data.exercise_dates
    last = max(recorded) if recorded else link_start
    return min((today - last).days, RECORD_LOOKBACK_DAYS)


def _recent_days(today: date) -> list[date]:
    return [today - timedelta(days=i) for i in range(RECENT_WINDOW_DAYS, 0, -1)]


def _recent_diet(data: _MemberData, today: date) -> list[tuple[int, float]]:
    """어제까지 최근 창에서 칼로리를 기록한 날의 (칼로리, 단백질)."""
    out = []
    for day in _recent_days(today):
        kcal, protein = data.diet_by_date.get(day.isoformat(), (0, 0.0))
        if kcal > 0:
            out.append((kcal, protein))
    return out


def _exercise_goal_percent(
    sessions: Iterable[ExerciseSession], profile: HealthProfile | None, today: date
) -> int:
    """이번 주 유형별 달성률(경과일 비례, 유형마다 100% 상한)의 평균(%).

    회원 앱 운동 현황 링은 `이번 주 누적 ÷ 주간 목표` 다. 주 중간에 그 값을 그대로
    견주면 수요일에 누구나 절반도 못 채운 것이 되므로, 목표를 지난 날 수만큼만
    나눠 받는다.
    """
    elapsed = today.weekday() + 1
    goals = {
        exercise_types.CARDIO: _positive(
            getattr(profile, "weekly_cardio_minutes", None), DEFAULT_WEEKLY_CARDIO_MINUTES
        ),
        exercise_types.STRENGTH: _positive(
            getattr(profile, "weekly_strength_sets", None), DEFAULT_WEEKLY_STRENGTH_SETS
        ),
        exercise_types.STRETCHING: _positive(
            getattr(profile, "weekly_flexibility_minutes", None),
            DEFAULT_WEEKLY_STRETCHING_MINUTES,
        ),
    }
    done = {kind: 0 for kind in goals}
    for row in sessions:
        kind = exercise_types.normalize(row.type)
        if kind not in done:
            continue
        done[kind] += exercise_service.sets_of(row) if kind == exercise_types.STRENGTH else row.minutes
    ratios = [
        min(done[kind] / (goal * elapsed / 7), 1.0) for kind, goal in goals.items()
    ]
    return round(sum(ratios) / len(ratios) * 100)


def _routine_missed_days(
    routines: list[TrainerRoutine], completed: set[tuple[str, date]], today: date
) -> int:
    """배정 루틴이 걸려 있던 날 수. 그중 하루라도 완료가 있으면 0."""
    assigned_days = 0
    for day in _recent_days(today):
        iso = day.isoformat()
        active = [
            r for r in routines
            if r.active_from <= iso and (r.ended_on is None or r.ended_on > iso)
        ]
        if not active:
            continue
        if any((r.id, day) in completed for r in active):
            return 0
        assigned_days += 1
    return assigned_days


def build_signals(
    db: Session, trainer_id: str, links: list[TrainerClient]
) -> dict[str, list[ClientSignalOut]]:
    """담당 링크마다의 신호, 급한 순. 담당 해제·휴면 링크는 빈 목록이다."""
    watched = [l for l in links if l.active and not l.dormant]
    out: dict[str, list[ClientSignalOut]] = {l.member_id: [] for l in links}
    if not watched:
        return out
    member_ids = [l.member_id for l in watched]
    today = clock.today()
    now = clock.now()
    lookback = today - timedelta(days=RECORD_LOOKBACK_DAYS)
    monday = today - timedelta(days=today.weekday())

    data = {
        m: _MemberData(diet_by_date={}, exercise_dates=set(), week_sessions=[])
        for m in member_ids
    }

    # 식단 — 날짜별 칼로리·단백질 합.
    diet_sum: dict[str, dict[str, list[float]]] = defaultdict(lambda: defaultdict(lambda: [0, 0.0]))
    for user_id, day, kcal, protein in db.execute(
        select(DietEntry.user_id, DietEntry.date, DietEntry.total_calories, DietEntry.protein_g)
        .where(DietEntry.user_id.in_(member_ids), DietEntry.date >= lookback.isoformat())
    ).all():
        cell = diet_sum[user_id][day]
        cell[0] += kcal or 0
        cell[1] += protein or 0.0
    for user_id, by_day in diet_sum.items():
        data[user_id].diet_by_date = {d: (int(v[0]), float(v[1])) for d, v in by_day.items()}

    # 운동 — 기록일(기록 끊김)과 이번 주 기록(운동 목표).
    for row in db.scalars(
        select(ExerciseSession).where(
            ExerciseSession.user_id.in_(member_ids),
            ExerciseSession.week_start >= (lookback - timedelta(days=lookback.weekday())).isoformat(),
        )
    ).all():
        day = exercise_activity.activity_date_of(row)
        if day is None or day < lookback or day > today:
            continue
        data[row.user_id].exercise_dates.add(day)
        if day >= monday:
            data[row.user_id].week_sessions.append(row)

    # 통증·불편 — 이 트레이너와의 채팅, AI 챗봇. 글만 본다(이모티콘 메시지는 본문이 비어 있다).
    cutoff = now - timedelta(days=DISCOMFORT_WINDOW_DAYS)
    texts: list[tuple[str, str]] = list(
        db.execute(
            select(ChatMessage.member_id, ChatMessage.body).where(
                ChatMessage.trainer_id == trainer_id,
                ChatMessage.member_id.in_(member_ids),
                ChatMessage.sender == "member",
                ChatMessage.created_at >= cutoff,
            )
        ).all()
    )
    texts += list(
        db.execute(
            select(AiConversation.user_id, AiMessage.content)
            .join(AiConversation, AiConversation.id == AiMessage.conversation_id)
            .where(
                AiConversation.user_id.in_(member_ids),
                AiMessage.role == "user",
                AiMessage.created_at >= cutoff,
                # 회원이 오탐이라며 치운 줄은 세지 않는다(#1975).
                AiMessage.insight_dismissed.is_(False),
            )
        ).all()
    )
    for member_id, text in texts:
        if data[member_id].discomfort:
            continue
        found = insights.detect(text)
        if found is not None and found.kind == insights.KIND_DISCOMFORT:
            data[member_id].discomfort = True

    # 노쇼·회원 사정 취소.
    for member_id, status, source in db.execute(
        select(
            TrainerSchedule.member_id,
            TrainerSchedule.status,
            TrainerSchedule.cancellation_source,
        ).where(
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.member_id.in_(member_ids),
            TrainerSchedule.date >= (today - timedelta(days=NO_SHOW_WINDOW_DAYS)).isoformat(),
            TrainerSchedule.date <= today.isoformat(),
            or_(
                TrainerSchedule.status == _SCHEDULE_NO_SHOW,
                TrainerSchedule.status == _SCHEDULE_CANCELLED,
            ),
        )
    ).all():
        if status == _SCHEDULE_NO_SHOW or source == _CANCELLED_BY_MEMBER:
            data[member_id].no_show_count += 1

    # 배정 루틴 — 최근 창에 걸려 있던 것과 그 완료.
    window_start = today - timedelta(days=RECENT_WINDOW_DAYS)
    yesterday = today - timedelta(days=1)
    routines_by_member: dict[str, list[TrainerRoutine]] = defaultdict(list)
    for r in db.scalars(
        select(TrainerRoutine).where(
            TrainerRoutine.trainer_id == trainer_id,
            TrainerRoutine.member_id.in_(member_ids),
            # 검토 대기·거절된 후보는 배정이 아니다(#790).
            TrainerRoutine.status == "approved",
            TrainerRoutine.active_from <= yesterday.isoformat(),
            or_(
                TrainerRoutine.ended_on.is_(None),
                TrainerRoutine.ended_on > window_start.isoformat(),
            ),
        )
    ).all():
        routines_by_member[r.member_id].append(r)
    completed: set[tuple[str, date]] = set()
    routine_ids = [r.id for rs in routines_by_member.values() for r in rs]
    if routine_ids:
        for row in db.scalars(
            select(ExerciseSession).where(
                ExerciseSession.assigned_routine_id.in_(routine_ids),
                ExerciseSession.week_start
                >= (window_start - timedelta(days=window_start.weekday())).isoformat(),
            )
        ).all():
            day = exercise_activity.activity_date_of(row)
            if day is not None:
                completed.add((row.assigned_routine_id, day))

    profiles = {
        p.user_id: p
        for p in db.scalars(
            select(HealthProfile).where(HealthProfile.user_id.in_(member_ids))
        ).all()
    }

    for link in watched:
        member_id = link.member_id
        member = data[member_id]
        profile = profiles.get(member_id)
        link_start = clock.to_seoul(link.created_at).date() if link.created_at else today
        found: list[ClientSignalOut] = []

        if member.discomfort:
            found.append(ClientSignalOut(kind=SIGNAL_DISCOMFORT))

        if (today - link_start).days < NEW_LINK_GRACE_DAYS:
            out[member_id] = found
            continue

        gap = _record_gap_days(member, link_start, today)
        if gap >= RECORD_GAP_DAYS:
            found.append(ClientSignalOut(kind=SIGNAL_RECORD_GAP, days=gap))

        if member.no_show_count >= NO_SHOW_MIN_COUNT:
            found.append(ClientSignalOut(kind=SIGNAL_NO_SHOW, count=member.no_show_count))

        missed = _routine_missed_days(routines_by_member.get(member_id, []), completed, today)
        if missed >= ROUTINE_MIN_ASSIGNED_DAYS:
            found.append(ClientSignalOut(kind=SIGNAL_ROUTINE_MISSED, days=missed))

        if today.weekday() >= EXERCISE_GOAL_FROM_WEEKDAY:
            percent = _exercise_goal_percent(member.week_sessions, profile, today)
            if percent < EXERCISE_GOAL_LOW_PERCENT:
                found.append(ClientSignalOut(kind=SIGNAL_EXERCISE_GOAL_LOW, percent=percent))

        recent = _recent_diet(member, today)
        if len(recent) >= MIN_RECORDED_DAYS:
            target = _positive(getattr(profile, "daily_calories", None), DEFAULT_CALORIE_TARGET_KCAL)
            mean_kcal = sum(k for k, _ in recent) / len(recent)
            if calorie_off_target(mean_kcal, target):
                gap_ratio = calorie_gap(mean_kcal, target)
                found.append(ClientSignalOut(
                    kind=SIGNAL_CALORIE_OFF,
                    percent=abs(round(gap_ratio * 100)),
                    direction="over" if gap_ratio > 0 else "under",
                ))

            protein_target = getattr(profile, "daily_protein_g", None)
            focus = set(health_focus.focus_in(getattr(profile, "conditions", None)))
            if protein_target and protein_target > 0 and focus & PROTEIN_FOCUS:
                mean_protein = sum(p for _, p in recent) / len(recent)
                if mean_protein < protein_target * PROTEIN_LOW_RATIO:
                    found.append(ClientSignalOut(
                        kind=SIGNAL_PROTEIN_LOW,
                        percent=round(mean_protein / protein_target * 100),
                    ))

        if any(s.kind == SIGNAL_RECORD_GAP for s in found):
            found = [s for s in found if s.kind not in _RECORD_DERIVED]
        found.sort(key=lambda s: SIGNAL_ORDER.index(s.kind))
        out[member_id] = found
    return out
