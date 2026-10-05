"""트레이너 도메인 — 주간 리포트·리포트 피드백 초안·주간 목표·보낸 리포트."""
from __future__ import annotations

import json
import re
import uuid
from collections.abc import Callable, Sequence
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone

from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.locale import Locale, current_locale
from app.core.week import monday_of
from app.models.models import (
    ChatMessage, DietEntry, ExerciseSession, HealthProfile,
    TrainerReportGoal,
    TrainerClient, TrainerReportFeedback,
    TrainerSchedule,
    User,
)
from app.schemas.trainer_api import (
    MemberReportSendOut,
    MemberReportSendsOut,
    ReportGoalsOut,
    ReportQueueItemOut,
    ReportQueueOut,
    ReportSendOut,
    ReportSendsOut,
    ReportFeedbackOut, WeeklyReportOut,
)
from app.services import (
    client_signals,
    data_consent_service,
    diet_coach_inputs,
)
from app.services import korean_josa
from app.services.trainer._common import (
    SCHEDULE_DONE,
    SCHEDULE_UPCOMING,
    SODIUM_TARGET_MG,
    _assigned_week_counts,
    _calories_week,
    _iso,
    _macro_week,
    _meal_counts,
    _sodium_week,
    _sugar_week,
    _week_days,
    week_completion_by_member,
)


# ---- 주간 리포트 ----


def week_start_of(day: date) -> date:
    """그 주의 월요일."""
    return monday_of(day)


def build_weekly_report(
    db: Session, trainer_id: str, member_id: str, week_start: date
) -> WeeklyReportOut:
    """담당 고객 한 명의 한 주.

    O2O 코칭에서 회원이 재등록하는 이유는 "좋아졌다"를 볼 수 있을 때다. 여기서
    쓰는 값은 전부 두 앱이 이미 공유하는 데이터(식단·운동기록·스케줄)이며 새로
    수집하는 것이 없다.
    """
    monday = week_start_of(week_start)
    sunday = monday + timedelta(days=6)
    monday_str, sunday_str = monday.isoformat(), sunday.isoformat()

    member = db.get(User, member_id)
    member_name = member.name if member else "고객"

    # 취소·노쇼는 세지 않는다(#871). `sessions_booked` 는 "이번 주에 잡혀 있던
    # 수업" 이고 리포트는 그 분모로 이행을 읽는다 — 진행되지 않은 약속을 분모에
    # 넣으면 트레이너 사정의 취소가 회원의 낮은 이행률로 보인다. 취소·노쇼
    # 자체에 패널티를 주는 지표는 이번 범위가 아니라 별도 정책이다.
    # 상담도 세지 않는다(#2741) — 리포트가 말하는 것은 **PT** 횟수다. 상담이 있던
    # 주는 PT 가 1회 더 나오고 이행률 분모도 그만큼 커졌다.
    sessions = db.scalars(
        select(TrainerSchedule).where(
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.member_id == member_id,
            TrainerSchedule.date >= monday_str,
            TrainerSchedule.date <= sunday_str,
            TrainerSchedule.status.in_((SCHEDULE_UPCOMING, SCHEDULE_DONE)),
            TrainerSchedule.type != "상담",
        )
    ).all()
    booked = len(sessions)
    done = sum(1 for s in sessions if s.status == SCHEDULE_DONE)

    # 요일 이행률은 로스터와 같은 계산이다(#2513) — 걸린 개인운동과 잡힌 PT.
    week = week_completion_by_member(db, trainer_id, [member_id], monday)[member_id]
    # 요일 칸은 회원의 실제 운동 기록에서 만든다(#1288). 기록이 (그 주 월요일,
    # 요일) 로 저장되므로 월요일 하나로 한 주가 그대로 걸린다.
    exercise_rows = db.scalars(
        select(ExerciseSession)
        .where(
            ExerciseSession.user_id == member_id,
            ExerciseSession.week_start == monday_str,
        )
        # 한 날에 여럿이면 한 순서로 적는다 — 정렬을 두지 않으면 같은 주를 두 번
        # 열 때 칸 안의 줄 순서가 바뀐다.
        .order_by(ExerciseSession.completed_at, ExerciseSession.id)
    ).all()
    assigned, assigned_done = _assigned_week_counts(db, trainer_id, member_id, monday)
    days = _week_days(list(exercise_rows), week, assigned, assigned_done)
    recorded = [d for d in week if d is not None]
    # 걸린 것이 하나도 없으면 null — 0% 로 보고하면 "아무것도 안 했다"는 거짓말이
    # 된다. 걸렸는데 안 한 날(0)은 평균에 든다(#2513).
    completion_avg = round(sum(recorded) / len(recorded)) if recorded else None

    diet = db.scalars(
        select(DietEntry).where(
            DietEntry.user_id == member_id,
            DietEntry.date >= monday_str,
            DietEntry.date <= sunday_str,
        )
    ).all()
    diet_rows = list(diet)
    sodium_week = _sodium_week(diet_rows, monday)
    # 기록이 있는 날만 센다 — 아직 오지 않은 요일의 0 까지 나누면 주 초반
    # 평균이 실제보다 낮아진다(로스터의 `sodiumWeekAvg` 와 같은 규칙).
    recorded_sodium = [mg for mg in sodium_week if mg > 0]
    sodium_avg = (
        round(sum(recorded_sodium) / len(recorded_sodium)) if recorded_sodium else None
    )

    # 회원이 적어 둔 하루 목표. 없으면 null 로 두고 판정 쪽이 공통 상수로
    # 되돌아간다 — 여기서 상수를 채워 보내면 화면이 '이 회원의 목표'와
    # '기본값'을 구분할 수 없다(#1430).
    profile = db.scalars(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    ).first()
    # 초과일은 그 회원의 나트륨 목표로 센다(#2885). 같은 응답의 `sodium_target`
    # 과 AI 요약이 개인 목표를 적는데 초과일만 2,000mg 으로 세면, 1,500mg 목표인
    # 회원의 1,800mg 날이 목표 안으로, 2,300mg 목표인 회원의 2,100mg 날이 초과로
    # 읽혔다. 목표가 없으면 공통 기준이다.
    sodium_limit = sodium_limit_mg(profile.daily_sodium_mg if profile else None)
    sodium_over_days = sum(1 for mg in sodium_week if mg > sodium_limit)

    report = WeeklyReportOut(
        calorie_baseline=_calorie_baseline(db, member_id, monday),
        member_id=member_id,
        member_name=member_name,
        calorie_target=profile.daily_calories if profile else None,
        sodium_target=profile.daily_sodium_mg if profile else None,
        sugar_target=profile.daily_sugar_g if profile else None,
        carbs_target=profile.daily_carbs_g if profile else None,
        protein_target=profile.daily_protein_g if profile else None,
        effective_protein_target=diet_coach_inputs.effective_protein_g(profile),
        fat_target=profile.daily_fat_g if profile else None,
        week_start=monday_str,
        week_end=sunday_str,
        sessions_booked=booked,
        sessions_done=done,
        completion_avg=completion_avg,
        sodium_over_days=sodium_over_days,
        sodium_avg=sodium_avg,
        week_completion=week,
        days=days,
        sodium_week=sodium_week,
        calories_week=_calories_week(diet_rows, monday),
        sugar_week=_sugar_week(diet_rows, monday),
        carbs_week=_macro_week(diet_rows, monday, lambda e: e.carbs_g),
        protein_week=_macro_week(diet_rows, monday, lambda e: e.protein_g),
        fat_week=_macro_week(diet_rows, monday, lambda e: e.fat_g),
        meal_counts=_meal_counts(diet_rows, monday),
        message="",
    )
    return report.model_copy(update={"message": report_message(report)})


def sodium_limit_mg(target: int | None) -> int:
    """나트륨 초과를 가르는 하루 기준(mg) — 회원 목표, 없으면 공통 기준. (#2885)

    0 이하는 "목표 없음" 으로 읽는다(앱의 목표 읽기와 같은 규칙).
    """
    return target if target is not None and target > 0 else SODIUM_TARGET_MG


#: 칼로리 `평소` 가 견주는 직전 주 수. 한 주만 보면 그 주가 아프거나 출장이었을
#: 때 기준 자체가 거짓이 된다 — 트레이너 웹 `kCalorieBaselineWeeks` 와 같다.
CALORIE_BASELINE_WEEKS = 4


def _calorie_baseline(db: Session, member_id: str, monday: date) -> float | None:
    """[monday] 주 직전 4주에 **기록한 날**의 하루 평균 칼로리. 없으면 None. (#2863)

    앱이 직전 4주 리포트를 하나씩 다시 읽어 `calories_week` 의 0 아닌 날을
    평균 내던 계산을 그대로 옮겼다 — 날마다 합을 반올림한 뒤(`_calories_week`
    와 같은 규칙) 0 인 날은 뺀다. 안 적은 날을 0 으로 세면 성실히 적은 주가
    오히려 적게 먹은 주로 보인다.
    """
    start = monday - timedelta(days=7 * CALORIE_BASELINE_WEEKS)
    end = monday - timedelta(days=1)
    rows = db.execute(
        select(DietEntry.date, func.sum(DietEntry.total_calories))
        .where(
            DietEntry.user_id == member_id,
            DietEntry.date >= start.isoformat(),
            DietEntry.date <= end.isoformat(),
        )
        .group_by(DietEntry.date)
    ).all()
    recorded = [round(total or 0) for _, total in rows]
    recorded = [kcal for kcal in recorded if kcal > 0]
    if not recorded:
        return None
    return sum(recorded) / len(recorded)


def build_report_queue(db: Session, trainer_id: str, week: date) -> ReportQueueOut:
    """[week] 주 리포트 작업대 — 열람할 수 있는 담당 회원 전원의 요약. (#2863)

    작업대는 담당 회원 전원을 한 화면에 세운다. 예전에는 앱이 회원마다 주간
    리포트와 회원 피드백을 따로 불러(회원 N명이면 요청 2N개) 서버도 회원마다
    `build_weekly_report` 를 돌렸다. 큐가 쓰는 값은 세션 예약·완료 수와 이행률
    뿐이라, 그 값만 회원 id 목록으로 **묶어** 읽는다 — 회원 수와 무관하게 쿼리
    수가 정해져 있다.

    값의 규칙은 [build_weekly_report] 와 같다. 회원이 볼 수 있는 링크
    (`_require_client` 와 같은 조건: 담당이 살아 있고 동의가 철회되지 않음)만
    싣는다 — 회원 리포트가 404 인 회원의 수치를 여기로 새게 하지 않는다.
    """
    monday = week_start_of(week)
    sunday = monday + timedelta(days=6)
    monday_str, sunday_str = monday.isoformat(), sunday.isoformat()
    member_ids = list(
        db.scalars(
            select(TrainerClient.member_id)
            .where(
                TrainerClient.trainer_id == trainer_id,
                TrainerClient.active.is_(True),
                data_consent_service.allows_access_clause(),
            )
            .order_by(TrainerClient.member_id)
        ).all()
    )
    if not member_ids:
        return ReportQueueOut(week_start=monday_str, items=[])

    # 세션 — 리포트와 같이 취소·노쇼·상담은 세지 않는다(#871, #2741).
    booked: dict[str, int] = defaultdict(int)
    done: dict[str, int] = defaultdict(int)
    for member_id, status in db.execute(
        select(TrainerSchedule.member_id, TrainerSchedule.status).where(
            TrainerSchedule.trainer_id == trainer_id,
            TrainerSchedule.member_id.in_(member_ids),
            TrainerSchedule.date >= monday_str,
            TrainerSchedule.date <= sunday_str,
            TrainerSchedule.status.in_((SCHEDULE_UPCOMING, SCHEDULE_DONE)),
            TrainerSchedule.type != "상담",
        )
    ).all():
        booked[member_id] += 1
        if status == SCHEDULE_DONE:
            done[member_id] += 1

    # 이행률 — 리포트와 같은 `week_completion_by_member` 규칙(#2513): 걸린
    # 개인운동과 잡힌 PT. 회원 수와 무관하게 쿼리 셋이다.
    week_by_member = week_completion_by_member(db, trainer_id, member_ids, monday)

    items: list[ReportQueueItemOut] = []
    for member_id in member_ids:
        week_values = week_by_member.get(member_id, [None] * 7)
        recorded = [d for d in week_values if d is not None]
        items.append(
            ReportQueueItemOut(
                member_id=member_id,
                sessions_booked=booked.get(member_id, 0),
                sessions_done=done.get(member_id, 0),
                completion_avg=(
                    round(sum(recorded) / len(recorded)) if recorded else None
                ),
                week_completion=week_values,
            )
        )
    return ReportQueueOut(week_start=monday_str, items=items)


def report_message(report: WeeklyReportOut, locale: Locale | None = None) -> str:
    """회원 채팅 스레드에 그대로 들어갈 본문.

    별도 리포트 함이 아니라 이미 읽고 있는 대화에 도착하도록 평문으로 쓴다 —
    시스템 덤프가 아니라 담당 트레이너가 쓴 말처럼 보여야 한다.

    리포트 요약 카드(`trainer_report_summary_service`)와 **역할이 다르다.**
    카드는 트레이너가 훑는 메모라 짧고 건조하다. 이 글은 회원이 받는 편지라
    문단으로 쓰고, 수치마다 그래서 무엇을 하면 되는지를 붙인다. 트레이너가
    손보지 않고 그대로 보내도 사람이 쓴 것으로 읽혀야 한다.

    기록이 없는 항목은 문장을 아예 뺀다 — '이행률 0%'는 거짓말이다.

    [locale] 은 초안을 쓰는 트레이너 화면의 언어다(#2298). 생략하면 지금 요청의
    언어이고, 헤더가 없으면 지금까지처럼 한국어다. 영어 문장은 트레이너 웹의
    `reportBody*` 문구와 같은 말투로 쓴다 — 서버 초안과 화면 초안이 다른 사람이
    쓴 글처럼 읽히면 안 된다.
    """
    if (locale or current_locale()) == "en":
        return _report_message_en(report)
    return _report_message_ko(report)


def _report_message_ko(report: WeeklyReportOut) -> str:
    """한국어 본문. 헤더가 없는 요청과 한국어 화면이 받는 지금까지의 문장이다."""
    start = date.fromisoformat(report.week_start)
    end = date.fromisoformat(report.week_end)
    good = (
        (report.completion_avg or 0) >= client_signals.COMPLETION_GOOD_PERCENT
        and report.sodium_over_days <= 2
    )
    period = f"{start.month}월 {start.day}일 – {end.month}월 {end.day}일"

    paragraphs: list[str] = [
        # 첫 줄에 무슨 메시지인지가 있어야 한다 — 회원의 대화방에는 다른
        # 메시지도 함께 쌓인다.
        f"{report.member_name}님, {period} 주간 리포트 정리해서 보내드려요."
    ]

    workout: list[str] = []
    if report.completion_avg is not None:
        # `이번 주` 로 시작하지 않는다 — 지난 주 리포트에도 그대로 나가는
        # 문장이고, 어느 주인지는 첫 줄의 날짜 범위가 이미 말한다(#1177).
        # 좋음·보통·낮음 세 구간 — 75% 에게 "잘 따라오셨어요" 도, "많이
        # 바쁘셨나 봐요" 도 맞지 않는다(#2345).
        if report.completion_avg >= client_signals.COMPLETION_GOOD_PERCENT:
            line = f"운동은 평균 {report.completion_avg}%로 잘 따라오셨어요."
        elif report.completion_avg >= client_signals.COMPLETION_LOW_PERCENT:
            line = f"운동은 평균 {report.completion_avg}%로 꾸준히 해 주셨어요."
        else:
            line = f"운동 이행률은 평균 {report.completion_avg}%였어요. 많이 바쁘셨나 봐요."
        workout.append(line)
    skipped = _skipped_names(report)
    if skipped:
        workout.append(
            f"다만 {_topic(', '.join(skipped))} 건너뛰셨더라고요. 컨디션 때문이었다면 "
            "다음 PT 때 말씀해 주세요. 대체 동작으로 바꿔 둘게요."
        )
    if workout:
        paragraphs.append(" ".join(workout))

    diet: list[str] = []
    # 초과일을 센 기준과 같은 목표를 적는다(#2885).
    sodium_limit = sodium_limit_mg(report.sodium_target)
    if report.sodium_avg is not None:
        # 평균과 초과일을 한 문장에 뒤섞지 않는다. `평균 1,916mg으로 목표를
        # 3일 넘겼어요` 는 평균이 목표를 넘긴 것처럼 읽힌다. 목표도 문장에
        # 박아 두지 않는다 — 기준이 바뀌면 문장만 옛말을 한다(#1177).
        diet.append(
            f"나트륨은 하루 평균 {report.sodium_avg:,}mg이었고, "
            f"목표({sodium_limit:,}mg)를 넘긴 날이 "
            f"{report.sodium_over_days}일이었어요. 국물을 절반만 남기셔도 "
            "하루 400~500mg은 줄어듭니다."
            if report.sodium_over_days > 0
            else f"나트륨은 하루 평균 {report.sodium_avg:,}mg으로 "
            f"목표({sodium_limit:,}mg) 안에서 잘 지키고 계세요."
        )
    recorded = [v for v in report.calories_week if v > 0]
    if recorded:
        diet.append(
            f"칼로리는 하루 평균 {round(sum(recorded) / len(recorded)):,}kcal이에요."
        )
    if diet:
        paragraphs.append(" ".join(diet))

    if len(paragraphs) == 1:
        # 인사말만 남았다 — 가리킬 '이 부분'이 없다. 기록이 없는 주에 격려부터
        # 하면 회원이 무엇을 하라는 말인지 알 수 없다.
        paragraphs.append(
            "이 주에는 남은 기록이 없어서 정리해 드릴 내용이 없네요. "
            "다음 주 시작을 같이 잡아 봐요."
        )
    else:
        paragraphs.append(
            "정말 잘하셨어요. 다음 주도 이 페이스 그대로 가요!"
            if good
            else "다음 주에는 이 부분만 같이 신경 써 봐요. 루틴은 제가 조정해서 올려둘게요."
        )
    return "\n\n".join(paragraphs)


def _plural_days(n: int) -> str:
    """영어 날 수(`1 day`·`3 days`)."""
    return f"{n} day" if n == 1 else f"{n} days"


def _report_message_en(report: WeeklyReportOut) -> str:
    """영어 본문. 한국어 본문과 같은 문단·같은 판정이고 문장만 영어다."""
    start = date.fromisoformat(report.week_start)
    end = date.fromisoformat(report.week_end)
    good = (
        (report.completion_avg or 0) >= client_signals.COMPLETION_GOOD_PERCENT
        and report.sodium_over_days <= 2
    )
    # 트레이너 웹 `dateMonthDay`·`dateRange` 와 같은 모양(`8/10 – 8/16`).
    period = f"{start.month}/{start.day} – {end.month}/{end.day}"

    paragraphs: list[str] = [
        f"Hi {report.member_name}, here's your weekly report for {period}."
    ]

    workout: list[str] = []
    if report.completion_avg is not None:
        if report.completion_avg >= client_signals.COMPLETION_GOOD_PERCENT:
            line = f"You kept up well — {report.completion_avg}% of your workouts done."
        elif report.completion_avg >= client_signals.COMPLETION_LOW_PERCENT:
            line = f"You stayed steady — {report.completion_avg}% of your workouts done."
        else:
            line = (
                f"Workout completion came in at {report.completion_avg}%. "
                "Sounds like a busy week."
            )
        workout.append(line)
    skipped = _skipped_names(report)
    if skipped:
        workout.append(
            f"One thing — {', '.join(skipped)} got skipped. If that was down to how "
            "you were feeling, tell me at our next PT and I'll swap in an "
            "alternative."
        )
    if workout:
        paragraphs.append(" ".join(workout))

    diet: list[str] = []
    sodium_limit = sodium_limit_mg(report.sodium_target)
    if report.sodium_avg is not None:
        diet.append(
            f"Sodium averaged {report.sodium_avg:,}mg a day, and went over the "
            f"{sodium_limit:,}mg target on {_plural_days(report.sodium_over_days)}. "
            "Leaving half the broth behind saves 400–500mg a day."
            if report.sodium_over_days > 0
            else f"Sodium averaged {report.sodium_avg:,}mg a day — comfortably "
            f"inside the {sodium_limit:,}mg target."
        )
    recorded = [v for v in report.calories_week if v > 0]
    if recorded:
        diet.append(
            f"Calories averaged {round(sum(recorded) / len(recorded)):,}kcal a day."
        )
    if diet:
        paragraphs.append(" ".join(diet))

    if len(paragraphs) == 1:
        paragraphs.append(
            "There's nothing logged for this week, so nothing to sum up. "
            "Let's plan next week's start together."
        )
    else:
        paragraphs.append(
            "Great work — let's keep this pace next week!"
            if good
            else "Let's focus on just these things next week. "
            "I'll adjust your program and send it over."
        )
    return "\n\n".join(paragraphs)


def _topic(word: str) -> str:
    """`은`/`는` 을 받침에 맞춰 붙인다.

    `은(는)` 은 사람이 쓴 글로 읽히지 않는다 — 회원이 그대로 받는 문장이라
    기계가 쓴 티가 나는 자리를 남기지 않는다. 규칙은 서버·두 앱이 함께 쓰는
    `korean_josa` 하나다(#2897) — `레그 프레스(머신)` 은 괄호 앞 글자로,
    `플랭크 60` 은 읽는 소리로 고른다.
    """
    if not word:
        return word
    return korean_josa.with_particle(word, "은", "는")


def _skipped_names(report: WeeklyReportOut) -> list[str]:
    """그 주에 건너뛴 운동 이름. 이행률이 왜 100%가 아닌지의 답이다.

    분량을 뗀 이름으로 묶는다 — 같은 스트레칭을 요일마다 건너뛰면 예전에는
    `하체 스트레칭 10분, 하체 스트레칭 5분, 하체 스트레칭 15분` 이 되어, 서로
    다른 운동 셋을 빠뜨린 것처럼 읽혔다(#1177).
    """
    names: list[str] = []
    for day in report.days:
        for line in day.exercises:
            if "✗" not in line:
                continue
            name = exercise_base_name(line)
            if name and name not in names:
                names.append(name)
    return names[:3]


#: 운동 이름 뒤에 붙는 그날의 분량(`하체 스트레칭 10분`, `벤치프레스 4세트 · 10회 · 40kg`).
_EXERCISE_AMOUNT_RE = re.compile(r"\s*\d+(?:\.\d+)?\s*(?:분|초|kg|km|회|세트)$")


def exercise_base_name(line: str) -> str:
    """운동 한 줄에서 분량 표기를 떼어 낸 이름.

    초안·요약이 운동을 **묶어 세는** 자리에서는 분량이 같은 운동을 서로 다른
    운동으로 갈라 놓는다. 앱의 `exerciseBaseName` 과 같은 규칙이다(#1177).
    """
    name = line.replace("✗", "").replace("✓", "").strip()
    head, sep, _ = name.partition("·")
    if sep:
        name = head.strip()
    return _EXERCISE_AMOUNT_RE.sub("", name).strip()


# ---- 리포트 피드백 초안 (#821) ----


def get_report_feedback(
    db: Session, trainer_id: str, member_id: str, week: date
) -> ReportFeedbackOut:
    """그 주에 저장해 둔 피드백 초안. 없으면 빈 본문으로 답한다.

    404 를 쓰지 않는 이유: 초안이 없는 것은 오류가 아니라 아직 쓰지 않은
    정상 상태다. 화면은 빈 본문을 받으면 자동 생성 문구를 그대로 쓴다.
    """
    row = _report_feedback_row(db, trainer_id, member_id, week)
    return ReportFeedbackOut(
        member_id=member_id,
        week_start=week.isoformat(),
        body=row.body if row else "",
        updated_at=row.updated_at if row else None,
    )


def save_report_feedback(
    db: Session, trainer_id: str, member_id: str, week: date, body: str
) -> ReportFeedbackOut:
    """그 주의 피드백 초안을 저장한다. 같은 주에 다시 저장하면 덮어쓴다.

    편집기가 항목 단위 diff 가 아니라 입력창의 현재 전체 문구를 들고 있으므로
    통째로 교체한다. 빈 문자열도 유효한 저장이다 — 트레이너가 지운 것을
    "저장한 적 없음" 으로 되돌리면 다음에 열 때 지운 문구가 되살아난다.
    """
    row = _report_feedback_row(db, trainer_id, member_id, week)
    now = datetime.now(timezone.utc)
    if row is None:
        row = TrainerReportFeedback(
            id=f"rfb-{uuid.uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            week_start=week.isoformat(),
            body=body,
            created_at=now,
            updated_at=now,
        )
        db.add(row)
    else:
        row.body = body
        row.updated_at = now
    db.commit()
    db.refresh(row)
    return ReportFeedbackOut(
        member_id=member_id,
        week_start=week.isoformat(),
        body=row.body,
        updated_at=row.updated_at,
    )


def _report_feedback_row(
    db: Session, trainer_id: str, member_id: str, week: date
) -> TrainerReportFeedback | None:
    return db.scalar(
        select(TrainerReportFeedback).where(
            TrainerReportFeedback.trainer_id == trainer_id,
            TrainerReportFeedback.member_id == member_id,
            TrainerReportFeedback.week_start == week.isoformat(),
        )
    )


#: 한 주에 담을 수 있는 목표 수. 화면이 ③ 에서 이만큼을 한 번에 보여 준다 —
#: 스무 줄짜리 목표 목록은 다음 주에 아무도 회수하지 않는다.
_MAX_REPORT_GOALS = 20

#: 목표 한 줄의 길이. 트레이너가 자기 말로 적는 자리라 짧게 막지 않되,
#: 회원 앱 목표 칸이 한 화면에 담을 수 있는 선에서 끊는다.
_MAX_REPORT_GOAL_LENGTH = 120


def get_report_goals(db: Session, member_id: str, week: date) -> ReportGoalsOut:
    """그 주에 적용돼 있는 목표. 없으면 빈 목록이다.

    비어 있는 것이 오류가 아닌 까닭은 `get_report_feedback` 과 같다 — 지난
    주에 아무것도 고르지 않았거나 이 회원의 첫 주다. 404 로 만들면 리포트의
    ③ 칸이 통째로 사라진다.
    """
    row = db.scalar(
        select(TrainerReportGoal).where(
            TrainerReportGoal.member_id == member_id,
            TrainerReportGoal.week_start == week.isoformat(),
        )
    )
    goals: list[str] = []
    if row is not None:
        try:
            decoded = json.loads(row.goals_json)
        except json.JSONDecodeError:
            # 깨진 값은 "목표가 없다"로 읽는다 — 화면을 세우는 쪽이, 지어낸
            # 목표를 회원에게 보내는 것보다 낫다.
            decoded = []
        if isinstance(decoded, list):
            goals = [g for g in decoded if isinstance(g, str) and g.strip()]
    return ReportGoalsOut(week_start=week.isoformat(), goals=goals)


def _report_sends_query(trainer_id: str):
    """리포트 전송 메시지 — 트레이너가 보낸 것 중 `report_week_start` 를 실은 것.

    주 단위 조회(#2288)와 회원별 조회(#2393)가 같은 근거를 읽도록 조건을
    여기 한 곳에 둔다. 최신 전송이 먼저 오게 정렬해 두어 `_fold_report_sends`
    가 첫 행을 "가장 최근" 으로 잡는다.
    """
    return (
        select(ChatMessage)
        .where(
            ChatMessage.trainer_id == trainer_id,
            ChatMessage.sender == "trainer",
            ChatMessage.report_week_start.is_not(None),
        )
        .order_by(ChatMessage.created_at.desc(), ChatMessage.id.desc())
    )


def _fold_report_sends(
    rows: Sequence[ChatMessage], key: Callable[[ChatMessage], str]
) -> tuple[dict[str, ChatMessage], dict[str, int]]:
    """최신순 전송들을 [key] 마다 **가장 최근 것** 하나와 횟수로 접는다.

    주 단위 조회는 회원으로, 회원별 조회는 주로 접는다 — 접는 규칙이 두 벌이면
    같은 전송이 두 화면에서 다른 횟수로 보이는 날이 온다.
    """
    latest: dict[str, ChatMessage] = {}
    counts: dict[str, int] = defaultdict(int)
    for row in rows:
        k = key(row)
        latest.setdefault(k, row)
        counts[k] += 1
    return latest, counts


def list_report_sends(db: Session, trainer_id: str, week: date) -> ReportSendsOut:
    """[week] 주 리포트가 나간 담당 회원들. (#2288)

    근거는 리포트 전송이 남긴 채팅 메시지의 `report_week_start` 다. 본문 전송
    (`/report/send`)과 PDF 전송(`/report/send-pdf`)이 모두 이 값을 남기므로,
    어느 길로 보냈든 여기서 한 번에 보인다. 앱이 들고 있던 기록은 새로고침하면
    사라져, 이미 보낸 회원이 미전송으로 돌아가 같은 리포트가 두 번 나갔다.

    담당이 살아 있는 회원만 싣는다 — 해제된 회원의 기록은 다른 트레이너 화면
    에서 읽을 이유가 없고, 실으면 해제 사실이 응답으로 드러난다(#2281).
    한 회원에게 여러 번 보냈으면 **가장 최근 것** 하나로 접고 횟수를 함께 준다.
    """
    week_iso = week_start_of(week).isoformat()
    active_members = select(TrainerClient.member_id).where(
        TrainerClient.trainer_id == trainer_id,
        TrainerClient.active.is_(True),
    )
    rows = db.scalars(
        _report_sends_query(trainer_id).where(
            ChatMessage.report_week_start == week_iso,
            ChatMessage.member_id.in_(active_members),
        )
    ).all()
    latest, counts = _fold_report_sends(rows, lambda m: m.member_id)
    return ReportSendsOut(
        week_start=week_iso,
        sends=[
            ReportSendOut(
                member_id=member_id,
                week_start=week_iso,
                sent_at=_iso(msg.created_at),
                message=msg.body,
                read=msg.read_at is not None,
                has_pdf=_is_report_pdf(msg),
                send_count=counts[member_id],
            )
            for member_id, msg in latest.items()
        ],
    )


def _is_report_pdf(msg: ChatMessage) -> bool:
    return msg.attachment_type == "pdf" and msg.attachment_file_id is not None


#: 회원별 지난 리포트 목록이 싣는 본문 첫 줄의 길이. 한 줄 요약 칸에 들어가는
#: 선에서 끊는다 — 전문은 채팅 메시지에 그대로 있다.
REPORT_PREVIEW_LENGTH = 80


def report_feedback_preview(body: str) -> str:
    """본문의 비어 있지 않은 첫 줄. 길면 잘라 `…` 를 붙인다."""
    first = next((line.strip() for line in body.splitlines() if line.strip()), "")
    if len(first) <= REPORT_PREVIEW_LENGTH:
        return first
    return first[: REPORT_PREVIEW_LENGTH - 1].rstrip() + "…"


def list_member_report_sends(
    db: Session,
    trainer_id: str,
    member_id: str,
    *,
    limit: int,
    before: date | None = None,
) -> MemberReportSendsOut:
    """[member_id] 에게 나간 리포트를 주별로, 최신 주부터. (#2393)

    근거와 접는 규칙은 주 단위 조회(`list_report_sends`)와 같다 — 한 주에 여러
    번 보냈으면 가장 최근 것 하나와 횟수. 담당 링크 확인은 라우터가
    `_require_client` 로 먼저 한다(#2281).

    쪽은 **주** 단위로 나눈다. 전송 한 건씩 자르면 같은 주의 재전송이 쪽 경계에
    걸려 횟수가 두 쪽에 나뉘어 실린다. 주 시작일은 이 목록에서 겹치지 않으므로
    커서는 그 값 하나(`before`, 그 주 제외)로 충분하다. 주 중간 날짜를 주면
    그 주 월요일로 접는다.
    """
    week_q = (
        select(ChatMessage.report_week_start)
        .where(
            ChatMessage.trainer_id == trainer_id,
            ChatMessage.member_id == member_id,
            ChatMessage.sender == "trainer",
            ChatMessage.report_week_start.is_not(None),
        )
        .group_by(ChatMessage.report_week_start)
        .order_by(ChatMessage.report_week_start.desc())
        .limit(limit + 1)
    )
    if before is not None:
        # 저장값이 `YYYY-MM-DD` 라 문자열 비교가 곧 날짜 비교다.
        week_q = week_q.where(
            ChatMessage.report_week_start < week_start_of(before).isoformat()
        )
    weeks = [w for w in db.scalars(week_q).all() if w]
    has_more = len(weeks) > limit
    weeks = weeks[:limit]
    if not weeks:
        return MemberReportSendsOut(member_id=member_id)

    rows = db.scalars(
        _report_sends_query(trainer_id).where(
            ChatMessage.member_id == member_id,
            ChatMessage.report_week_start.in_(weeks),
        )
    ).all()
    latest, counts = _fold_report_sends(rows, lambda m: m.report_week_start or "")
    return MemberReportSendsOut(
        member_id=member_id,
        sends=[
            MemberReportSendOut(
                week_start=week,
                sent_at=_iso(latest[week].created_at),
                read=latest[week].read_at is not None,
                send_count=counts[week],
                message_id=latest[week].id,
                has_pdf=_is_report_pdf(latest[week]),
                feedback_preview=report_feedback_preview(latest[week].body),
            )
            for week in weeks
        ],
        next_before=weeks[-1] if has_more else None,
    )


def save_report_goals(
    db: Session,
    trainer_id: str,
    member_id: str,
    week: date,
    goals: Sequence[str],
) -> ReportGoalsOut:
    """② 에서 고른 목표를 [week] **다음 주**에 적용한다.

    고른 주가 아니라 지켜야 할 주에 저장하는 것이 핵심이다 — 다음 주 리포트가
    자기 주의 목표를 그대로 꺼내 ③ 으로 회수한다. 고른 주에 저장하면 회수하는
    쪽이 매번 한 주를 빼야 하고, 주 경계를 두 곳에서 계산하는 순간 한쪽만
    틀리는 날이 온다.
    """
    applies = week_start_of(week) + timedelta(days=7)
    cleaned: list[str] = []
    for raw in goals:
        text = raw.strip()
        if not text:
            continue
        if len(text) > _MAX_REPORT_GOAL_LENGTH:
            raise HTTPException(status_code=422, detail="목표가 너무 깁니다.")
        # 같은 목표가 두 줄로 서면 다음 주 ③ 이 같은 판정을 두 번 적는다.
        if text not in cleaned:
            cleaned.append(text)
    if len(cleaned) > _MAX_REPORT_GOALS:
        raise HTTPException(status_code=422, detail="목표가 너무 많습니다.")

    now = datetime.now(timezone.utc)
    row = db.scalar(
        select(TrainerReportGoal).where(
            TrainerReportGoal.member_id == member_id,
            TrainerReportGoal.week_start == applies.isoformat(),
        )
    )
    if row is None:
        row = TrainerReportGoal(
            id=f"rg-{uuid.uuid4().hex[:12]}",
            trainer_id=trainer_id,
            member_id=member_id,
            week_start=applies.isoformat(),
            goals_json=json.dumps(cleaned, ensure_ascii=False),
            created_at=now,
            updated_at=now,
        )
        db.add(row)
    else:
        # 담당이 바뀐 주에도 목록은 하나다 — 마지막에 정한 트레이너로 바꿔 둔다.
        row.trainer_id = trainer_id
        row.goals_json = json.dumps(cleaned, ensure_ascii=False)
        row.updated_at = now
    db.commit()
    return ReportGoalsOut(week_start=applies.isoformat(), goals=cleaned)
