"""로스터 확장 회원(4~15번)의 주간 지표 시드.

트레이너 웹의 목업 로스터(`frontend/flutter_trainer/lib/core/storage/seed_clients.dart`)
는 고객 15명을 **화면 상태의 fixture** 로 설계했다 — 나트륨 초과, 이행률 저조, 휴면,
답장 대기, 짧은 스파크라인 같은 상태를 클릭만으로 도달할 수 있게 하려고 고른 숫자다.
실 API 시드는 3명뿐이라 실서버로 전환하면 그 상태 대부분이 재현되지 않았다(#572).

여기서는 **지표를 만들 최소 기록만** 넣는다. 로스터의 주간 지표는 저장 필드가 아니라
실데이터에서 계산되기 때문이다(`trainer._common._sodium_week` /
`week_completion_by_member`).
따라서 "계정만 만들고 지표를 채운다"는 불가능하고, 하루치 식단·운동 기록이 곧 지표다.

기존 3명(김민수·이지수·박성호)의 풍부한 상세 데이터(끼니별 음식·피드백·트레이너 메모·
채팅·스케줄)는 `seed_member_data.py` 가 계속 담당한다. 여기 12명은 로스터·차트·경고가
동작할 만큼만 채우고 상세는 비운다.
"""
from __future__ import annotations

import json
import logging
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core import clock
from app.core.week import monday_of
from app.db import seed_workouts
from app.db.session import SessionLocal
from app.models import models
from app.services import exercise_activity

logger = logging.getLogger(__name__)

#: 목업 로스터에서 옮긴 주간 지표.
#:
#: * ``sodium``  — 최근 7일 일별 나트륨(오래된→오늘). `_sodium_week` 가 날짜별 합으로 읽는다.
#: * ``completion`` — 이번 주 월→일 일별 완료율. 이행률은 그날 걸린 개인운동 중 한
#:   비율이라(#2513), 그 주에 개인운동 한 벌을 걸고 비율만큼 완료를 남긴다. 처음과
#:   끝의 0 은 "아무것도 걸리지 않은 날"(기록 없음)이라 그 날에는 걸지 않고, 사이의
#:   0 은 "걸렸는데 안 한 날"(0%)이다.
#: * ``awaiting`` — 회원이 마지막으로 말한 채로 남은 스레드(답장 대기 배지).
#:
#: 7개보다 짧은 나트륨 배열은 의도된 것이다 — 기록이 끊겼거나(문가영) 이제 막
#: 시작한(노은채) 고객의 짧은 스파크라인을 그리기 위한 값이다. 끊긴 쪽은 과거에,
#: 시작한 쪽은 오늘에 붙인다.
_METRICS: dict[str, dict] = {
    "user-hayun": {  # 정하윤 — V자: 무너졌다 회복, 나트륨 급락 후 반등
        "sodium": [2900, 2600, 1500, 1250, 1400, 1900, 1650],
        "completion": [100, 25, 0, 0, 50, 100, 100],
        "awaiting": False,
    },
    "user-woojin": {  # 최우진 — 완벽한 주(경고 0). 정상 상태의 기준선
        "sodium": [1300, 1250, 1100, 1200, 1150, 1090, 1180],
        "completion": [100, 100, 100, 100, 100, 100, 100],
        "awaiting": False,
    },
    "user-kangseoyeon": {  # 강서연 — 주중 완벽, 주말에 나트륨 폭발
        "sodium": [1400, 1350, 1500, 1420, 1380, 3100, 2750],
        "completion": [100, 100, 100, 100, 100, 0, 0],
        "awaiting": False,
    },
    "user-dohyun": {  # 임도현 — 기록 전무(빈 상태 화면)
        "sodium": [],
        "completion": [0, 0, 0, 0, 0, 0, 0],
        "awaiting": False,
    },
    "user-sera": {  # 오세라 — 우하향: 이행률 붕괴 + 나트륨 상승
        "sodium": [1900, 2150, 2400, 2650, 2900, 3050, 3250],
        "completion": [80, 60, 40, 33, 20, 0, 0],
        "awaiting": True,
    },
    "user-junhyuk": {  # 배준혁 — 야근형: 이행률 저조 + 나트륨 들쭉날쭉
        "sodium": [2100, 2600, 1800, 2900, 2200, 1600, 2280],
        "completion": [50, 0, 33, 0, 25, 0, 0],
        "awaiting": True,
    },
    "user-yuna": {  # 신유나 — 회복 중: 나트륨 우하향, 이행률 우상향
        "sodium": [2800, 2500, 2200, 1950, 1800, 1750, 1720],
        "completion": [0, 0, 33, 67, 100, 100, 100],
        "awaiting": False,
    },
    "user-jiho": {  # 한지호 — 정체기: 목표선 위아래로 진동(경계값)
        "sodium": [1990, 2010, 1995, 2005, 1998, 2015, 2010],
        "completion": [67, 67, 67, 67, 67, 67, 67],
        "awaiting": False,
    },
    "user-gayoung": {  # 문가영 — 휴면: 주 3일치만 기록되고 끊김
        "sodium": [2100, 1950, 1030],
        "completion": [33, 0, 0, 0, 0, 0, 0],
        "awaiting": True,
        "anchor": "past",
    },
    "user-taekyung": {  # 류태경 — 극단: 0↔100, 1200↔3200 지그재그
        "sodium": [1200, 3100, 1350, 2950, 1100, 3200, 3100],
        "completion": [100, 0, 100, 0, 100, 0, 0],
        "awaiting": True,
    },
    "user-seojin": {  # 백서진 — 운동은 완벽한데 나트륨만 계속 초과
        "sodium": [2400, 2550, 2700, 2600, 2800, 2650, 2680],
        "completion": [100, 100, 100, 100, 100, 100, 100],
        "awaiting": False,
    },
    "user-eunchae": {  # 노은채 — 단 하루만 기록(단일 포인트 스파크라인)
        "sodium": [1450],
        "completion": [100, 0, 0, 0, 0, 0, 0],
        "awaiting": False,
        "anchor": "today",
    },
}

#: 데모 리포트 이력이 거슬러 올라가는 주 수(이번 주 포함). 트레이너 웹의
#: `demoReportHistoryWeeks` 와 같은 값이다.
DEMO_REPORT_HISTORY_WEEKS = 14

#: 지난 리포트의 칼로리 줄이 평소로 삼는 앞선 주 수. 트레이너 웹의
#: `kCalorieBaselineWeeks` 와 같은 값이다.
CALORIE_BASELINE_WEEKS = 4

#: 시드가 채우는 과거 주 수(이번 주 포함). 리포트가 '최근 4주' 카드를 그리고
#: 과거 주로 이동할 수 있어, 이번 주만 채우면 한 주만 뒤로 가도 화면이 빈다(#752).
#:
#: 리포트 이력의 가장 오래된 주도 그 앞 4주가 있어야 `지난 4주 평균` 과 증감이
#: 선다(#2453). 12주에 멈춰 있을 때는 오래된 지난 리포트가 `이번 주 평균` 만
#: 보여 줬다. 그래서 이력 주 수에 기준 주 수를 더한다. `seed_member_data` 도
#: 이 값을 그대로 쓴다.
HISTORY_WEEKS = DEMO_REPORT_HISTORY_WEEKS + CALORIE_BASELINE_WEEKS
_HISTORY_WEEKS = HISTORY_WEEKS

#: 과거 주에 곱하는 계수 — **지표마다 따로** 둔다. 난수를 쓰면 재시딩마다
#: 이력이 바뀌어 어제 본 화면과 달라지므로 고정된 수를 돌려 쓴다.
#:
#: 예전에는 하나를 나눠 쓰고 폭도 ±11% 뿐이라 12주 내내 나트륨은 늘 초과하고
#: 칼로리는 늘 목표 안이었다. 리포트의 목표선이 지표마다 한쪽 경우만 보여
#: 준다는 뜻이다. 계수를 갈라 회식이 몰린 주와 코칭이 먹힌 주가 함께 나오게
#: 한다. index 0 은 이번 주라 반드시 1.0 이다.
_SODIUM_FACTORS = (1.0, 0.96, 1.14, 0.82, 1.07, 0.78, 1.10)
_CALORIE_FACTORS = (1.0, 0.92, 1.28, 0.88, 1.04, 0.95, 1.13)
_SUGAR_FACTORS = (1.0, 1.12, 1.55, 0.88, 1.30, 0.96, 1.42)
#: 이행률은 좁게 흔든다 — 넓히면 100 에 붙어 잘려 여러 주가 같은 값이 된다.
_COMPLETION_FACTORS = (1.0, 0.94, 1.08, 0.9, 1.05, 0.97, 1.11)
_DAY_LABELS = ("월", "화", "수", "목", "금", "토", "일")

#: 칼로리 대비 당류 비율. 당류를 나트륨에서 끌어내면(예전 `나트륨/60`) 둘이
#: 늘 붙어 다녀, 당류만 넘긴 주가 나올 수 없다.
_SUGAR_PER_KCAL = 0.022

#: 상세 기록은 기존 3명만 둔다. 여기 12명의 식단은 지표를 만들기 위한 한 줄짜리다.
_MEAL_NAME = "기록된 식사"
#: 회원마다 받은 개인운동 기간(=운동 탭 `전체` 의 링) 모양. (#2508)
#:
#: 예전에는 모두가 지난 18주 내내 매주 한 벌을 받아 링 수가 똑같았다. 트레이너가
#: 회원마다 다르게 보낸 모습이 보이게 주 수를 나눈다. 임도현은 표에 없다 — 오늘
#: 처음 보낸 한 벌만 있다([_seed_new_member_routines]).
#:
#: * ``weeks`` — 이번 주부터 거슬러 몇 주 동안 매주 한 벌을 보냈나. 한 벌은 그 주
#:   ``completion`` 의 처음~끝 0 이 아닌 요일에 걸린다(로스터 이번 주 모양 그대로).
#:   그보다 앞선 주에도 같은 요일에 한 벌이 걸리지만 개인운동이 아닌 일반 배정이라
#:   링이 아니다 — 리포트 이력의 이행률은 예전 그대로 남는다.
#: * ``split`` — {거슬러 몇 주: 요일(월=0)} — 그 주 것을 7일을 못 채우고 그 요일에
#:   새 것으로 바꿨다. 링이 하나 더 생긴다.
#: * ``trend`` — 거슬러 몇 주의 이행률 배수(없으면 1.0). 링 완료율의 흐름이다.
#: * ``next_week`` — 다음 주 첫날부터 걸 한 벌을 어제 미리 보냈다(#2656: 보낸 날은
#:   전송일, 이번 주 것은 새 시작일 전날까지 그대로).
#:
#: 데모(`frontend/flutter_trainer/lib/core/storage/seed_rings.dart`)와 같은 표다.
_RING_PLAN: dict[str, dict] = {
    "user-hayun": {  # 정하윤 — 오래 받음, 가운데 주들이 꺼진 V자
        "weeks": 15,
        "trend": (1.0, 0.94, 0.88, 0.82, 0.76, 0.7, 0.64, 0.6,
                  0.64, 0.7, 0.76, 0.82, 0.88, 0.94, 1.0),
    },
    "user-woojin": {"weeks": 7, "next_week": True},  # 최우진 — 다음 주 것도 미리
    "user-kangseoyeon": {"weeks": 4},  # 강서연
    "user-sera": {  # 오세라 — 받을수록 떨어진다(주별 계수의 흔들림을 상쇄한 값)
        "weeks": 7,
        "trend": (1.0, 1.19, 1.15, 1.51, 1.41, 1.65, 1.55),
    },
    "user-junhyuk": {"weeks": 2, "split": {1: 3}},  # 배준혁 — 지난주 목요일에 교체
    "user-yuna": {"weeks": 1},  # 신유나 — 이번 주 처음
    "user-jiho": {"weeks": 15},  # 한지호
    "user-gayoung": {"weeks": 2},  # 문가영
    "user-taekyung": {"weeks": 3, "split": {2: 2}},  # 류태경 — 2주 전 수요일에 교체
    "user-seojin": {"weeks": 15},  # 백서진
    "user-eunchae": {"weeks": 1},  # 노은채 — 이번 주 처음
}

#: 이 시드가 만드는 배정·운동 기록 행의 id 접두사. 표에 없는 옛 행은 지운다 —
#: 남기면 링이 18개로 돌아간다.
_ROUTINE_PREFIX = "seed-roster-rt-"
_SESSION_PREFIX = "seed-roster-ex-"
_AWAITING_TEXT = "트레이너님, 이번 주 루틴 관련해서 여쭤볼 게 있어요."


def seed_roster_metrics() -> None:
    """확장 회원의 주간 지표용 최소 기록을 시드(멱등)."""
    db: Session = SessionLocal()
    try:
        for member_id, spec in _METRICS.items():
            if db.get(models.User, member_id) is None:
                continue  # 계정 시드가 건너뛴 회원(이메일 충돌 등)
            _seed_sodium_days(db, member_id, spec)
            _seed_completion_days(db, member_id, spec["completion"])
            if not any(spec["completion"]):
                _seed_new_member_routines(db, member_id)
            _seed_member_logs(db, member_id)
            if spec.get("awaiting"):
                _seed_awaiting_message(db, member_id)
        db.commit()
    finally:
        db.close()


def _sodium_offsets(values: list[int], anchor: str) -> list[tuple[int, int]]:
    """(오늘로부터 며칠 전, 나트륨) 목록.

    7개면 6일 전~오늘에 그대로 얹는다. 짧으면 [anchor] 를 따른다 — 기록이 끊긴
    고객은 과거에, 이제 시작한 고객은 오늘에 붙어야 스파크라인이 이야기와 맞는다.
    """
    if not values:
        return []
    if len(values) >= 7:
        return [(6 - i, v) for i, v in enumerate(values[-7:])]
    if anchor == "today":
        return [(len(values) - 1 - i, v) for i, v in enumerate(values)]
    return [(6 - i, v) for i, v in enumerate(values)]


def _seed_sodium_days(db: Session, member_id: str, spec: dict) -> None:
    today = clock.today()
    offsets = _sodium_offsets(spec["sodium"], spec.get("anchor", "recent"))
    # 이미 있는 날짜를 **한 번에** 읽는다 — 날마다 조회하면 여러 주 × 15명에서
    # 시딩이 눈에 띄게 느려진다.
    existing = _existing_diet_ids(db, member_id)
    for week in range(_HISTORY_WEEKS):
        idx = week % len(_SODIUM_FACTORS)
        for offset, base in offsets:
            _seed_one_sodium_day(
                db, member_id, today, offset + week * 7, base,
                _SODIUM_FACTORS[idx], _CALORIE_FACTORS[idx],
                _SUGAR_FACTORS[idx], existing,
            )


def _existing_diet_ids(db: Session, member_id: str) -> set[str]:
    return set(
        db.scalars(
            select(models.DietEntry.id).where(models.DietEntry.user_id == member_id)
        ).all()
    )


def _seed_one_sodium_day(
    db: Session,
    member_id: str,
    today: date,
    offset: int,
    base: int,
    sodium_factor: float,
    calorie_factor: float,
    sugar_factor: float,
    existing: set[str],
) -> None:
    sodium = round(base * sodium_factor)
    date_str = (today - timedelta(days=offset)).isoformat()
    entry_id = f"seed-roster-diet-{member_id}-{date_str}"
    # 끼니로 나눈 날(`seed_member_logs`, #2729)에는 한 줄을 다시 깔지 않는다 —
    # 그날 합계는 나눈 끼니가 이미 들고 있다.
    if entry_id in existing or f"seed-meal-{member_id}-{date_str}-0" in existing:
        return
    existing.add(entry_id)
    # 하루 한 줄. 끼니별 상세는 기존 3명만 가진다.
    #
    # 나트륨에서 칼로리를 끌어낸다 — 한 사람의 하루라 둘이 따로 놀면 안 된다.
    # 예전 산식(500 + 나트륨/10)은 2,000mg 짜리 하루를 700kcal 로 만들어,
    # 국물만 먹고 사는 사람처럼 보였다. 1.1~1.5mg/kcal 은 짜게 먹는 한식의
    # 실제 범위다. 거기에 그 주의 식사량을 얹는다 — 계수가 갈라져 있어야
    # 칼로리만 넘긴 주, 나트륨만 잡힌 주가 따로 나온다.
    base_kcal = 900 + (sodium * 3) // 10
    calories = round(base_kcal * calorie_factor)
    sugar = round(base_kcal * _SUGAR_PER_KCAL * sugar_factor, 1)
    db.add(models.DietEntry(
        id=entry_id,
        user_id=member_id,
        date=date_str,
        meal_type="lunch",
        time_label="12:30",
        foods_json=json.dumps(
            [{"name": _MEAL_NAME, "calories": calories}], ensure_ascii=False
        ),
        total_calories=calories,
        sodium_mg=sodium,
        sugar_g=sugar,
    ))


def ring_windows(
    completion: list[int], plan: dict, today: date
) -> list[tuple[date, date, int, bool]]:
    """(걸린 첫날, 끝난 날(그날은 안 걸림), 거슬러 몇 주, 개인운동인가) 목록.

    오래된 것부터다. 지난 [_HISTORY_WEEKS] 주 모두 한 주에 한 벌이 그 주 처음~끝
    요일에 걸리고, 최근 ``weeks`` 주만 개인운동(링)이다 — 그 앞은 일반 배정이라
    리포트 이행률은 예전 그대로다. 미리 보낸 다음 주 것(``next_week``)도 들어
    있다. 데모 `demoRingWindows` 와 같은 규칙이다.
    """
    active = [i for i, rate in enumerate(completion) if rate > 0]
    if not active or not plan:
        return []
    first, last = active[0], active[-1]
    this_monday = monday_of(today)
    split: dict[int, int] = plan.get("split", {})
    windows: list[tuple[date, date, int, bool]] = []
    for week in reversed(range(_HISTORY_WEEKS)):
        monday = this_monday - timedelta(days=7 * week)
        begin = monday + timedelta(days=first)
        end = monday + timedelta(days=last + 1)
        if begin > today:
            continue  # 이번 주 것을 아직 보내지 않았다(수요일부터 받는 회원의 월·화)
        personal = week < plan["weeks"]
        cut = split.get(week)
        if personal and cut is not None and first < cut <= last:
            windows.append((begin, monday + timedelta(days=cut), week, True))
            begin = monday + timedelta(days=cut)
        windows.append((begin, end, week, personal))
    if plan.get("next_week"):
        start = this_monday + timedelta(days=7 + first)
        windows.append((start, start + timedelta(days=7), -1, True))
    return windows


def ring_factor(plan: dict, week: int) -> float:
    """거슬러 [week] 주의 이행률 계수 — 주 계수 × 흐름. 데모 하루 지표와 같은 값이다."""
    trend = plan.get("trend", ())
    return _COMPLETION_FACTORS[week % len(_COMPLETION_FACTORS)] * (
        trend[week] if week < len(trend) else 1.0
    )


def _ring_sent_on(today: date) -> date:
    """`next_week` 한 벌을 보낸 날 — 어제, 이번 주 월요일보다 앞서지는 않는다."""
    return max(today - timedelta(days=1), monday_of(today))


def _seed_completion_days(db: Session, member_id: str, completion: list[int]) -> None:
    """회원이 받은 한 벌마다 그 회원의 개인운동을 걸고 그날 비율만큼 완료를 남긴다(멱등). (#2513, #3003, #2508)

    이행률은 저장값이 아니라 그날 걸린 배정과 완료에서 계산된다
    (`trainer_service.week_completion_by_member`). 예전처럼 `routine_history` 에
    비율을 적으면 아무 화면도 읽지 않는다.

    - 운동은 회원별 표([seed_workouts.ROUTINES])다 — 트레이너 웹 데모의 `aiRoutine`
      과 같은 이름·양·강도. 완료는 배정 순서 앞에서부터 이행률만큼이고(데모
      `_RateDone` 과 같은 셈), 오늘도 그만큼 체크해 둔다 — `N개 중 M개 완료` 와
      `예상 소모` 가 함께 보인다.
    - 기간은 [_RING_PLAN] 이 정한다 — 최근 몇 주만 `개인운동만` 이라 운동 탭 `전체`
      의 링 수가 회원마다 다르다([ring_windows]).
    - id 가 날짜에서 나오므로 주가 바뀌면 표에 없는 옛 행을 지운다. 이미 깔린 행은
      지금 값으로 고친다(옛 공통 운동이 남지 않게).
    """
    from app.db.seed_trainer import TRAINER_ID

    routines = seed_workouts.ROUTINES.get(member_id, ())
    plan = _RING_PLAN.get(member_id, {})
    today = clock.today()
    now = clock.now()
    windows = ring_windows(completion, plan, today) if routines else []
    if not windows:
        return  # 기록 전무 — 개인운동을 받은 적 없는 회원이다(임도현은 따로 건다)
    routine_rows = {
        row.id: row
        for row in db.scalars(
            select(models.TrainerRoutine).where(
                models.TrainerRoutine.member_id == member_id,
                models.TrainerRoutine.id.like(f"{_ROUTINE_PREFIX}%"),
                models.TrainerRoutine.id.notlike(f"{_ROUTINE_PREFIX}{member_id}-new-%"),
            )
        ).all()
    }
    session_rows = {
        row.id: row
        for row in db.scalars(
            select(models.ExerciseSession).where(
                models.ExerciseSession.user_id == member_id,
                models.ExerciseSession.id.like(f"{_SESSION_PREFIX}%"),
            )
        ).all()
    }
    kept_routines: set[str] = set()
    kept_sessions: set[str] = set()
    for begin, end, week, personal in windows:
        sent = _ring_sent_on(today) if begin > today else begin
        kind = "" if personal else "std-"
        ids: list[str] = []
        for order, routine in enumerate(routines):
            routine_id = (
                f"{_ROUTINE_PREFIX}{member_id}-{kind}{begin.isoformat()}-{order}"
            )
            ids.append(routine_id)
            kept_routines.add(routine_id)
            row = routine_rows.get(routine_id)
            if row is None:
                row = models.TrainerRoutine(
                    id=routine_id,
                    trainer_id=TRAINER_ID,
                    member_id=member_id,
                    status="approved",
                )
                db.add(row)
            _apply_routine(row, routine, order)
            row.delivery_kind = "routine_only" if personal else None
            row.active_from = begin.isoformat()
            row.ended_on = end.isoformat()
            row.exercise_date = begin.isoformat() if personal else None
            row.created_at = min(exercise_activity.noon(sent), now)
        day = begin
        while day < end and day <= today:
            back = (monday_of(today) - monday_of(day)).days // 7
            weekday = day.weekday()
            rate = seed_workouts.day_rate(completion, weekday, ring_factor(plan, back))
            done = seed_workouts.done_count(rate, len(routines))
            late = seed_workouts.is_late_day(member_id, day, done, today)
            for order in range(done):
                routine = routines[order]
                session_id = f"{_SESSION_PREFIX}{member_id}-{day.isoformat()}-{order}"
                kept_sessions.add(session_id)
                row = session_rows.get(session_id)
                if row is None:
                    row = models.ExerciseSession(
                        id=session_id,
                        user_id=member_id,
                        source="assigned_routine",
                        assigned_trainer_id=TRAINER_ID,
                    )
                    db.add(row)
                at = exercise_activity.noon(day)
                if late and order == done - 1:
                    # 다음 날 체크 — 운동한 날(`week_start`·`day_label`)은 그대로다.
                    at = min(exercise_activity.noon(day + timedelta(days=1)), now)
                strength = routine.strength
                row.week_start = monday_of(day).isoformat()
                row.day_label = _DAY_LABELS[weekday]
                row.type = routine.code
                row.name = routine.name
                row.minutes = routine.minutes
                row.calories = seed_workouts.kcal(routine.code, routine.minutes)
                row.sets = routine.sets if strength else None
                row.reps = routine.reps if strength else None
                row.hold_seconds = routine.hold_seconds if strength else None
                row.weight = routine.weight if strength else None
                row.intensity = routine.intensity
                row.assigned_routine_id = ids[order]
                row.assigned_routine_name = routine.name
                row.completed_at = at
                row.created_at = at
            day += timedelta(days=1)
    # 표에 없는 옛 행 — 세션 먼저(배정을 가리킨다).
    for session_id, row in session_rows.items():
        if session_id not in kept_sessions:
            db.delete(row)
    for routine_id, row in routine_rows.items():
        if routine_id not in kept_routines:
            db.delete(row)
    db.flush()


def _apply_routine(
    row: models.TrainerRoutine, routine: seed_workouts.SeedRoutine, order: int
) -> None:
    """배정 행에 표의 값을 싣는다 — 새 행과 이미 깔린 행이 같은 값이 된다."""
    strength = routine.strength
    # 출처도 데모와 같다 — 시드 개인운동은 `AI 추천 · 트레이너 확인` 이다(데모
    # `seedAiRoutineExercise`). 예전에는 `trainer` 라 화면 문구가 갈렸다.
    row.source = "ai"
    row.name = routine.name
    row.minutes = routine.minutes
    row.type = routine.type
    row.reason = routine.reason
    row.sets = routine.sets if strength else None
    row.reps = routine.reps if strength else None
    row.hold_seconds = routine.hold_seconds if strength else None
    row.weight = routine.weight if strength else None
    row.intensity = routine.intensity
    row.sort_order = order + 1


def _seed_new_member_routines(db: Session, member_id: str) -> None:
    """기록이 없는 신규 회원(임도현)에게 **오늘 보낸** 개인운동만 건다(멱등). (#3003)

    지난 날 기록은 두지 않는다 — 빈 상태를 보여 주는 회원이다. 오늘 보낸 개인운동은
    오늘부터 7일 걸린다(트레이너가 `개인운동만` 을 보낸 것과 같다). 데모도 같은
    날에 같은 세 운동을 보낸 것으로 둔다.
    """
    from app.db.seed_trainer import TRAINER_ID

    routines = seed_workouts.ROUTINES.get(member_id, ())
    today = clock.today()
    for order, routine in enumerate(routines):
        routine_id = f"seed-roster-rt-{member_id}-new-{order}"
        row = db.get(models.TrainerRoutine, routine_id)
        if row is None:
            row = models.TrainerRoutine(
                id=routine_id,
                trainer_id=TRAINER_ID,
                member_id=member_id,
                source="ai",
                status="approved",
                delivery_kind="routine_only",
            )
            db.add(row)
        _apply_routine(row, routine, order)
        row.active_from = today.isoformat()
        row.ended_on = (today + timedelta(days=7)).isoformat()
        row.exercise_date = today.isoformat()
        row.created_at = min(exercise_activity.noon(today), clock.now())


def _seed_member_logs(db: Session, member_id: str) -> None:
    """회원이 직접 적은 운동([seed_workouts.MEMBER_LOGS]) — 지난 날 그 요일마다 한 줄(멱등). (#3003)

    출처 `member` 라 트레이너 화면의 `회원 추가` 로 선다. 트레이너 웹 데모의
    `_memberLogs` 와 같은 요일·같은 값이다. 이행률에는 들지 않는다 — 해야 할 목록이
    없는 운동이다(`week_completion_by_member`).
    """
    logs = seed_workouts.MEMBER_LOGS.get(member_id, ())
    if not logs:
        return
    today = clock.today()
    this_monday = monday_of(today)
    for week in range(_HISTORY_WEEKS):
        monday = this_monday - timedelta(days=7 * week)
        for i, (weekday, exercise) in enumerate(logs):
            day = monday + timedelta(days=weekday)
            if day >= today:
                continue
            session_id = f"seed-roster-mx-{member_id}-{day.isoformat()}-{i}"
            if db.get(models.ExerciseSession, session_id) is not None:
                continue
            at = exercise_activity.noon(day)
            db.add(models.ExerciseSession(
                id=session_id,
                user_id=member_id,
                week_start=monday.isoformat(),
                day_label=_DAY_LABELS[weekday],
                type=exercise.type,
                name=exercise.name,
                minutes=exercise.minutes,
                calories=exercise.calories,
                sets=exercise.sets,
                reps=exercise.reps,
                weight=exercise.weight,
                intensity=exercise.intensity,
                source="member",
                completed_at=at,
                created_at=at,
            ))


def _seed_awaiting_message(db: Session, member_id: str) -> None:
    """회원이 마지막으로 말한 채로 남은 스레드(답장 대기 배지)."""
    from app.db.seed_trainer import TRAINER_ID

    msg_id = f"seed-roster-chat-{member_id}"
    if db.get(models.ChatMessage, msg_id) is not None:
        return
    exists = db.scalar(
        select(models.ChatMessage.id)
        .where(
            models.ChatMessage.trainer_id == TRAINER_ID,
            models.ChatMessage.member_id == member_id,
        )
        .limit(1)
    )
    if exists is not None:
        return
    db.add(models.ChatMessage(
        id=msg_id,
        trainer_id=TRAINER_ID,
        member_id=member_id,
        sender="member",
        body=_AWAITING_TEXT,
        created_at=clock.now(),
    ))
