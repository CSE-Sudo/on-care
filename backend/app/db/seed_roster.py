"""로스터 확장 회원(4~15번)의 주간 지표 시드.

트레이너 웹의 목업 로스터(`frontend/flutter_trainer/lib/core/storage/seed_clients.dart`)
는 고객 15명을 **화면 상태의 fixture** 로 설계했다 — 나트륨 초과, 이행률 저조, 휴면,
답장 대기, 짧은 스파크라인 같은 상태를 클릭만으로 도달할 수 있게 하려고 고른 숫자다.
실 API 시드는 3명뿐이라 실서버로 전환하면 그 상태 대부분이 재현되지 않았다(#572).

여기서는 **지표를 만들 최소 기록만** 넣는다. 로스터의 주간 지표는 저장 필드가 아니라
실데이터에서 계산되기 때문이다(`trainer_service._sodium_week` / `_week_completion`).
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
from app.db.session import SessionLocal
from app.models import models

logger = logging.getLogger(__name__)

#: 목업 로스터에서 옮긴 주간 지표.
#:
#: * ``sodium``  — 최근 7일 일별 나트륨(오래된→오늘). `_sodium_week` 가 날짜별 합으로 읽는다.
#: * ``completion`` — 이번 주 월→일 일별 완료율. `_week_completion` 이 날짜별 최댓값으로 읽는다.
#:   0 인 날은 "기록 없음" 이므로 행을 만들지 않는다(경고 규칙이 0 을 평균에서 제외한다).
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

#: 칼로리 대비 당류 비율. 당류를 나트륨에서 끌어내면(예전 `나트륨/60`) 둘이
#: 늘 붙어 다녀, 당류만 넘긴 주가 나올 수 없다.
_SUGAR_PER_KCAL = 0.022

#: 상세 기록은 기존 3명만 둔다. 여기 12명의 식단은 지표를 만들기 위한 한 줄짜리다.
_MEAL_NAME = "기록된 식사"
_ROUTINE_LABEL = "AI 개인운동"
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


def _seed_completion_days(db: Session, member_id: str, completion: list[int]) -> None:
    today = clock.today()
    this_monday = monday_of(today)
    existing = set(
        db.scalars(
            select(models.RoutineHistory.id).where(
                models.RoutineHistory.member_id == member_id
            )
        ).all()
    )
    for week in range(_HISTORY_WEEKS):
        monday = this_monday - timedelta(days=7 * week)
        factor = _COMPLETION_FACTORS[week % len(_COMPLETION_FACTORS)]
        for i, rate in enumerate(completion):
            if rate <= 0:
                continue  # 기록 없음 — 행을 만들면 '0% 수행'이라는 다른 뜻이 된다
            day = monday + timedelta(days=i)
            if day > today:
                continue  # 아직 오지 않은 요일
            date = day.isoformat()
            hist_id = f"seed-roster-hist-{member_id}-{date}"
            if hist_id in existing:
                continue
            existing.add(hist_id)
            db.add(models.RoutineHistory(
                id=hist_id,
                member_id=member_id,
                trainer_id=None,
                date=date,
                kind_label=_ROUTINE_LABEL,
                completion_rate=min(100, round(rate * factor)),
                exercises_json=json.dumps([], ensure_ascii=False),
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
