"""
식단 도메인 서비스 — 라우터에서 분리한 집계·코칭·저장 로직.

diet 라우터가 오늘 집계·나트륨 코칭·엔트리 저장/멱등을 직접 수행해 두꺼웠던 것을
여기로 이관한다(exercise_service/health_service 와 일관성). 동작·응답 계약은 불변이며,
라우터는 HTTP 관심사(업로드·인식기 디스패치·에러 매핑)만 담당한다.
"""
from __future__ import annotations

import json
import logging
import uuid
from dataclasses import dataclass
from datetime import date as date_type, timedelta

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.models.models import DietEntry
from app.schemas.diet import DietAnalysis, RecognizedFood
from app.schemas.diet_api import (
    DietEntryOut, DietEntryUpdate, DietTodayResponse, calculate_macros,
)
from app.services import diet_photo_service, period_window
from app.services.coach.personal_ingest import record_diet, refresh_diet

logger = logging.getLogger(__name__)

# foods_json 에 남기는 음식 필드. 음식별 탄단지도 여기 들어간다(#1892) — 인식기와
# 공공 DB 가 음식마다 내는 값이고(`nutrition/enrich.py`), 회원이 수정 모드에서 고치는
# 값도 이것이다(#1856). 버리면 끼니 합계만 남아 수정 화면이 음식마다 0 을 보여 주고,
# 회원이 고친 음식별 값도 저장되지 않는다.
_FOOD_STORAGE_FIELDS = (
    "name", "calories", "sodium_mg", "sugar_g",
    "carbs_g", "protein_g", "fat_g", "source",
)
# 음식에서 끼니 합계를 낼 때 쓰는 짝: 합계 컬럼 ← 음식 필드.
_TOTAL_FROM_FOOD = {
    "total_calories": "calories",
    "carbs_g": "carbs_g",
    "protein_g": "protein_g",
    "fat_g": "fat_g",
    "sodium_mg": "sodium_mg",
    "sugar_g": "sugar_g",
}
# 정수로 저장하는 합계 — 나머지는 소수다(#296).
_INTEGER_TOTALS = frozenset({"total_calories", "sodium_mg"})
# DASH 권고 나트륨 상한(고혈압 특화 코칭 기준).
DASH_SODIUM_LIMIT_MG = 2000


def today_str() -> str:
    return clock.today_iso()


def load_foods(foods_json: str) -> list[dict]:
    """저장된 foods_json → 표시용 음식 목록. 저장 대상 밖의 키는 버린다."""
    foods = json.loads(foods_json) if foods_json else []
    return [
        {field: food[field] for field in _FOOD_STORAGE_FIELDS if field in food}
        for food in foods
    ]


def store_foods(foods: list[RecognizedFood]) -> list[dict]:
    """RecognizedFood → foods_json 에 넣을 표현.

    사진 분석 저장과 회원의 수정이 **같은 표현**을 써야 한다. 한쪽만 필드를
    더하면 고친 뒤에 화면이 달라진다.
    """
    return [
        {field: getattr(food, field) for field in _FOOD_STORAGE_FIELDS}
        for food in foods
    ]


def totals_from_foods(foods: list[RecognizedFood]) -> dict[str, float | int]:
    """음식 목록 → 끼니 합계. 적히지 않은 값(None)은 0 으로 센다.

    끼니 합계는 음식별 값의 합이다 — 앱도 같은 규칙으로 화면에 더한다(#1853).
    음식이 오면 이 값이 함께 온 합계보다 우선한다: 원본을 하나로 두지 않으면
    음식을 고칠 때마다 합계와 내역이 갈린다.
    """
    totals: dict[str, float | int] = {}
    for column, field in _TOTAL_FROM_FOOD.items():
        total = sum(float(getattr(food, field) or 0) for food in foods)
        totals[column] = int(round(total)) if column in _INTEGER_TOTALS else total
    return totals


def entry_to_analysis(entry: DietEntry) -> DietAnalysis:
    """저장된 DietEntry → 분석 응답용 DietAnalysis(멱등 재시도 응답용).

    coach_comment 는 저장하지 않으므로 재시도 응답에선 비운다(엔트리는 이미 존재).
    끼니 macros/nutrient 합계는 DietEntry 를 단일 원본으로 그대로 반영한다.
    """
    foods_raw = json.loads(entry.foods_json) if entry.foods_json else []
    return DietAnalysis(
        engine=entry.engine or "",
        foods=[RecognizedFood(**f) for f in foods_raw],
        total_calories=entry.total_calories,
        total_carbs_g=entry.carbs_g,
        total_protein_g=entry.protein_g,
        total_fat_g=entry.fat_g,
        total_sodium_mg=entry.sodium_mg,
        total_sugar_g=entry.sugar_g,
        coach_comment="",
    )


def member_photo_url(photo_id: str) -> str:
    """회원 자신이 보는 사진 경로. API base 기준 상대 경로다."""
    return f"/diet/photos/{photo_id}"


def _entry_out(entry: DietEntry, photo_id: str | None = None) -> DietEntryOut:
    return DietEntryOut(
        id=entry.id, meal_type=entry.meal_type, time_label=entry.time_label,
        foods=load_foods(entry.foods_json), total_calories=entry.total_calories,
        carbs_g=entry.carbs_g, protein_g=entry.protein_g, fat_g=entry.fat_g,
        sodium_mg=entry.sodium_mg, sugar_g=entry.sugar_g,
        photo_url=member_photo_url(photo_id) if photo_id else None,
    )


def coach_message(total_sodium_mg: int, has_entries: bool) -> str:
    """오늘 나트륨 기준 코칭 메시지(고혈압 특화). DASH 권고 초과 시 경고."""
    if total_sodium_mg > DASH_SODIUM_LIMIT_MG:
        return "오늘 나트륨 섭취가 많았어요. 저녁은 담백한 구이/샐러드로 균형을 맞춰봐요!"
    if not has_entries:
        return "아직 오늘 식단 기록이 없어요. 첫 끼니를 기록해 볼까요?"
    return "균형 잡힌 하루였어요. 내일도 이대로 가요!"


#: 기간 조언이 다루는 구간. 정의는 [period_window] 하나뿐이다 — 운동 조언
#: (#1025)도 같은 구간을 봐야 해서 그리로 옮겼고, 여기서는 이름만 그대로
#: 이어 준다(이미 이 이름으로 부르는 자리가 있다).
PERIOD_TODAY = period_window.PERIOD_TODAY
PERIOD_WEEK = period_window.PERIOD_WEEK
PERIOD_ALL = period_window.PERIOD_ALL
ALL_PERIOD_DAYS = period_window.ALL_PERIOD_DAYS
period_bounds = period_window.period_bounds


def _weekday_split(days: list[DietDayTotals]) -> tuple[list[int], list[int]]:
    """(주중 나트륨, 주말 나트륨). 주말은 토·일이다."""
    weekday = [d.sodium_mg for d in days if d.date.weekday() < 5]
    weekend = [d.sodium_mg for d in days if d.date.weekday() >= 5]
    return weekday, weekend


def _avg(values: list[int]) -> float:
    return sum(values) / len(values) if values else 0


def period_coach_message(days: list[DietDayTotals], period: str) -> str:
    """기간에 맞는 식단 조언. (#1017, #1574)

    기간을 바꾸는 것은 "무엇을 볼지" 를 바꾸는 일이다. 그래프만 갈아 끼우고
    조언이 오늘 이야기로 남으면, 이번 주를 보고 있는데 "오늘 점심이 짰어요" 를
    읽게 되어 조언이 지금 화면과 무관한 말이 된다.

    기간마다 **재료가 다르다.** 오늘은 오늘 먹은 것, 이번 주는 요일별 편차와
    초과한 날 수, 전체는 주 단위 추세다. 말투도 다르다 — 오늘은 다음 끼니를
    제안하고, 이번 주·전체는 되짚어 준다.

    **한 문장 반을 넘기지 않는다.** 좁은 카드 안에서 길어질수록 정작 짚어야 할
    수치가 묻힌다 — 근거 하나와 다음 행동 하나면 충분하다. (#1574)
    """
    if not days:
        # 없는 기록으로 조언을 지어내지 않는다.
        if period == PERIOD_WEEK:
            return "이번 주 식단 기록이 아직 없어요. 한 끼만 남겨도 흐름이 보여요."
        if period == PERIOD_ALL:
            return "기록이 쌓이면 나트륨·칼로리 흐름을 짚어 드릴게요."
        return "오늘 식단 기록이 아직 없어요. 첫 끼니를 기록해 볼까요?"

    over = [d for d in days if d.over_sodium]

    if period == PERIOD_WEEK:
        if len(over) >= 3:
            return f"이번 주 {len(over)}일이나 나트륨을 넘겼어요. 국물은 건더기 위주로 드세요."
        weekday, weekend = _weekday_split(days)
        if weekend and weekday and _avg(weekend) > _avg(weekday) * 1.3:
            return "주중엔 잘 지키다 주말에 나트륨이 올라요. 주말 외식은 한 끼만 정해요."
        if over:
            return f"이번 주 {len(over)}일만 권장량을 넘었어요. 나머지 날의 균형은 좋았어요."
        return f"이번 주 {len(days)}일 모두 나트륨을 권장량 안에서 지켰어요!"

    if period == PERIOD_ALL:
        # 최근 4주와 그 이전을 견준다 — 나아지는 중인지가 이 화면의 질문이다.
        recent_from = days[-1].date - timedelta(days=27)
        recent = [d.sodium_mg for d in days if d.date >= recent_from]
        earlier = [d.sodium_mg for d in days if d.date < recent_from]
        if earlier and recent:
            if _avg(recent) < _avg(earlier) * 0.9:
                return "최근 4주 나트륨이 그 전보다 낮아졌어요. 지금 방식이 잘 맞아요."
            if _avg(recent) > _avg(earlier) * 1.1:
                return "최근 4주 나트륨이 다시 올라가고 있어요. 한 주만 되짚어 볼까요?"
        weekday, weekend = _weekday_split(days)
        if weekend and weekday and _avg(weekend) > _avg(weekday) * 1.3:
            return "기록을 통틀어 주말마다 나트륨이 올라요. 주말 한 끼만 담백하게 바꿔요."
        ratio = round(len(over) * 100 / len(days))
        if ratio >= 40:
            return f"기록한 날의 {ratio}%가 나트륨 권장량을 넘었어요. 국물부터 남겨 봐요."
        return f"기록한 {len(days)}일 대부분이 권장량 안이에요. 지금 흐름이 좋아요."

    # 오늘 — 그날 합계 하나로 말한다.
    today = days[-1]
    if today.over_sodium:
        return f"오늘 나트륨 {today.sodium_mg}mg 로 권장량을 넘겼어요. 남은 끼니는 담백하게."
    return f"오늘 나트륨 {today.sodium_mg}mg 로 권장량 안이에요. 이대로 마무리해요."


def build_day(db: Session, user_id: str, date: str) -> DietTodayResponse:
    """지정 날짜 식단 집계(칼로리·나트륨·당류·macros + 코칭 메시지)."""
    rows = db.scalars(
        select(DietEntry)
        .where(DietEntry.user_id == user_id, DietEntry.date == date)
        .order_by(DietEntry.created_at.asc())
    ).all()

    # 사진은 id 만 한 번에 읽는다 — 하루치 집계가 바이트까지 끌고 오면 안 된다.
    photo_ids = diet_photo_service.photo_ids_for_entries(db, [r.id for r in rows])
    entries: list[DietEntryOut] = [_entry_out(r, photo_ids.get(r.id)) for r in rows]
    total_cal = total_na = total_sugar = 0
    total_carbs = total_protein = total_fat = 0.0
    for r in rows:
        total_cal += r.total_calories
        total_carbs += r.carbs_g
        total_protein += r.protein_g
        total_fat += r.fat_g
        total_na += r.sodium_mg
        total_sugar += r.sugar_g

    return DietTodayResponse(
        entries=entries,
        total_calories=total_cal,
        total_sodium_mg=total_na,
        total_sugar_g=total_sugar,
        macros=calculate_macros(total_carbs, total_protein, total_fat),
        ai_coach_message=coach_message(total_na, bool(rows)),
    )


def build_today(db: Session, user_id: str) -> DietTodayResponse:
    """오늘 식단 집계. 기존 today 엔드포인트의 동작을 유지한다."""
    return build_day(db, user_id, today_str())


@dataclass(frozen=True)
class DietPeriodStats:
    """구간 내 일별 합계를 모은 값 — AI 코칭이 하루 스냅샷 대신 참고한다(#933).

    회원 앱 `dietRangeForTab` 이 화면에 보여주는 기간(이번 주=월~일, 이번 달=1일~말일)과
    같은 경계를 호출부가 맞춰 넘긴다고 가정한다. 여기서는 받은 구간을 그대로 집계한다.
    """

    days_logged: int
    days_over_sodium: int
    avg_sodium_mg: int
    avg_sugar_g: float
    avg_calories: int

    @property
    def empty(self) -> bool:
        return self.days_logged == 0


def period_stats(db: Session, user_id: str, start: str, end: str) -> DietPeriodStats:
    """[start, end](양끝 포함, `YYYY-MM-DD`) 구간의 일별 나트륨·당류·칼로리 평균.

    기록이 없는 날은 평균·초과일수 계산에서 빠진다 — 기록을 안 한 날까지 0으로
    넣으면 "며칠 기록했는지"와 "평균이 얼마인지"가 뒤섞여 실제보다 낮게 보인다.
    """
    rows = db.scalars(
        select(DietEntry)
        .where(DietEntry.user_id == user_id)
        .where(DietEntry.date >= start)
        .where(DietEntry.date <= end)
    ).all()

    daily: dict[str, dict[str, float]] = {}
    for r in rows:
        day = daily.setdefault(r.date, {"calories": 0, "sodium": 0, "sugar": 0.0})
        day["calories"] += r.total_calories
        day["sodium"] += r.sodium_mg
        day["sugar"] += r.sugar_g

    days_logged = len(daily)
    if days_logged == 0:
        return DietPeriodStats(0, 0, 0, 0.0, 0)

    days_over_sodium = sum(
        1 for d in daily.values() if d["sodium"] > DASH_SODIUM_LIMIT_MG
    )
    return DietPeriodStats(
        days_logged=days_logged,
        days_over_sodium=days_over_sodium,
        avg_sodium_mg=round(sum(d["sodium"] for d in daily.values()) / days_logged),
        avg_sugar_g=round(sum(d["sugar"] for d in daily.values()) / days_logged, 1),
        avg_calories=round(sum(d["calories"] for d in daily.values()) / days_logged),
    )


@dataclass(frozen=True)
class DietDayTotals:
    """하루치 합계. 기간 조언이 날짜별 패턴을 보려면 평균만으로는 부족하다. (#1017)"""

    date: date_type
    calories: int
    sodium_mg: int
    sugar_g: float

    @property
    def over_sodium(self) -> bool:
        return self.sodium_mg > DASH_SODIUM_LIMIT_MG


def daily_totals(
    db: Session, user_id: str, start: str, end: str
) -> list[DietDayTotals]:
    """[start, end] 구간의 **기록이 있는 날만** 날짜순으로. (#1017)

    기록이 없는 날을 0 으로 채우지 않는다 — 안 먹은 날과 기록 안 한 날은 다른
    말이고, 평균·패턴이 그 차이를 삼키면 조언이 사실과 어긋난다.
    """
    rows = db.scalars(
        select(DietEntry)
        .where(DietEntry.user_id == user_id)
        .where(DietEntry.date >= start)
        .where(DietEntry.date <= end)
    ).all()

    by_day: dict[str, dict[str, float]] = {}
    for r in rows:
        day = by_day.setdefault(r.date, {"calories": 0, "sodium": 0, "sugar": 0.0})
        day["calories"] += r.total_calories
        day["sodium"] += r.sodium_mg
        day["sugar"] += r.sugar_g

    out: list[DietDayTotals] = []
    for iso in sorted(by_day):
        try:
            when = date_type.fromisoformat(iso)
        except ValueError:
            continue
        totals = by_day[iso]
        out.append(
            DietDayTotals(
                date=when,
                calories=round(totals["calories"]),
                sodium_mg=round(totals["sodium"]),
                sugar_g=round(totals["sugar"], 1),
            )
        )
    return out


def find_by_idempotency(db: Session, user_id: str, key: str) -> DietEntry | None:
    return db.scalar(
        select(DietEntry).where(
            DietEntry.user_id == user_id, DietEntry.idempotency_key == key
        )
    )


def save_analyzed_entry(
    db: Session, user_id: str, meal_type: str, analysis: DietAnalysis,
    idempotency_key: str | None,
) -> tuple[DietEntry, bool]:
    """분석 결과를 diet_entries 에 저장. 반환: (entry, is_new).

    동시 재시도가 유니크 제약(user_id, idempotency_key)에 걸리면 이미 저장된 엔트리를
    반환한다(is_new=False, 중복 저장·재적재 방지). 신규 저장 시 개인 RAG 문서로도 적재.
    """
    foods_for_storage = store_foods(analysis.foods)
    # 날짜와 시각은 같은 시계 스냅샷에서 뽑는다. 따로 읽으면 KST 자정 사이에
    # date 는 어제, time_label 은 오늘이 되어 한 행 안에서 어긋난다.
    recorded_at = clock.now()
    entry = DietEntry(
        id=f"diet-{uuid.uuid4().hex[:12]}",
        user_id=user_id,
        date=recorded_at.date().isoformat(),
        meal_type=meal_type,
        time_label=recorded_at.strftime("%H:%M"),
        foods_json=json.dumps(foods_for_storage, ensure_ascii=False),
        total_calories=analysis.total_calories,
        carbs_g=analysis.total_carbs_g,
        protein_g=analysis.total_protein_g,
        fat_g=analysis.total_fat_g,
        sodium_mg=analysis.total_sodium_mg,
        sugar_g=analysis.total_sugar_g,
        engine=analysis.engine,
        idempotency_key=idempotency_key,
    )
    db.add(entry)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        existing = find_by_idempotency(db, user_id, idempotency_key) if idempotency_key else None
        if existing is not None:
            return existing, False
        raise
    db.refresh(entry)

    # 개인 RAG 문서로 적재(코치가 내 최근 식단을 검색하도록). 식단 저장은 이미
    # commit됐으므로 보조 인덱싱 실패가 성공 응답을 500으로 바꾸지 않게 격리한다.
    try:
        record_diet(
            db, user_id, date=entry.date, foods=foods_for_storage,
            total_calories=entry.total_calories, sodium_mg=entry.sodium_mg,
            sugar_g=entry.sugar_g, source_ref=entry.id,
        )
    except Exception as exc:  # noqa: BLE001 — 개인 RAG 적재는 best-effort
        db.rollback()
        logger.warning(
            "개인 RAG 적재 실패(%s) — 식단 저장은 유지",
            type(exc).__name__,
        )
    return entry, True


def get_owned_entry(db: Session, user_id: str, entry_id: str) -> DietEntry | None:
    return db.scalar(
        select(DietEntry).where(DietEntry.id == entry_id, DietEntry.user_id == user_id)
    )


class NutritionInconsistentError(ValueError):
    """영양 수치가 서로 어긋난다 — 당류가 탄수화물을 넘는 경우 등."""


def apply_entry_update(db: Session, entry: DietEntry, payload: DietEntryUpdate) -> DietEntryOut:
    """식단 기록의 날짜·끼니 분류/시간 + 영양소 부분 수정."""
    # 당류는 탄수화물의 일부다(총 탄수화물 = 당류 + 식이섬유 + 전분). 회원 화면도
    # 당류를 탄수화물 아래 들여 그 관계를 말하므로 서버도 같은 말을 해야 한다.
    #
    # 부분 수정이라 한쪽만 오는 일이 있어, 바꾸기 전에 **저장된 값과 합친 결과**로
    # 견준다. 인식 엔진 출력(`RecognizedFood`)에는 걸지 않는다 — 모델이 어긋난
    # 값을 낼 수 있는데 거기서 막으면 사진 분석 자체가 실패한다(#1863).
    #
    # 탄수화물이 0 이면 견주지 않는다. 컬럼이 NOT NULL 기본 0 이라 "탄수화물이
    # 없다" 와 "아직 안 적혔다" 를 구분할 수 없는데, 당류만 있고 탄수화물이 0 인
    # 기록은 거의 언제나 후자다(인식기가 그 값을 못 준 경우). 여기서 막으면
    # 탄수화물을 건드리지 않는 정상적인 부분 수정까지 거절된다.
    #
    # 음식 목록이 함께 오면 합계는 그 목록에서 다시 낸다(#1892). 견주는 값도
    # 저장된 합계가 아니라 이 값이어야 한다 — 아니면 방금 보낸 음식이 어긋나
    # 있어도 옛 합계로 통과한다.
    totals = totals_from_foods(payload.foods) if payload.foods is not None else None
    merged_carbs = (
        totals["carbs_g"] if totals is not None
        else payload.carbs_g if payload.carbs_g is not None
        else entry.carbs_g
    )
    merged_sugar = (
        totals["sugar_g"] if totals is not None
        else payload.sugar_g if payload.sugar_g is not None
        else entry.sugar_g
    )
    if (
        merged_carbs is not None
        and merged_carbs > 0
        and merged_sugar is not None
        and merged_sugar > merged_carbs
    ):
        raise NutritionInconsistentError(
            "당류는 탄수화물보다 클 수 없습니다. "
            f"당류 {merged_sugar}g, 탄수화물 {merged_carbs}g"
        )
    if payload.date is not None:
        # 날짜가 바뀌면 그 하루의 합계도 함께 옮겨진다 — 화면은 날짜별로 조회하므로
        # 이 값이 곧 "어느 날 먹은 것인가" 다(#1241).
        entry.date = payload.date
    if payload.meal_type is not None:
        entry.meal_type = payload.meal_type
    if payload.time_label is not None:
        entry.time_label = payload.time_label
    # 회원이 음식 하나하나를 고친 결과다(#1856). 이 자리에서 갈아 끼우지 않으면
    # 끼니 합계만 바뀌고 음식 내역은 옛것으로 남아, 한 기록 안에서 합계와
    # 내역이 어긋난다(#1892).
    if payload.foods is not None:
        entry.foods_json = json.dumps(store_foods(payload.foods), ensure_ascii=False)
    for field in ("total_calories", "carbs_g", "protein_g", "fat_g", "sodium_mg", "sugar_g"):
        value = totals[field] if totals is not None else getattr(payload, field)
        if value is not None:
            setattr(entry, field, value)
    db.commit()
    db.refresh(entry)
    out = _entry_out(entry)
    # 코치가 보는 근거도 함께 바뀌어야 한다(#603). 안 바꾸면 나트륨을 정정해도
    # 코치는 계속 옛 수치로 조언한다.
    # id 만 넘긴다 — 갱신은 잠금 안에서 행을 다시 읽는다(#614).
    refresh_diet(db, entry.user_id, entry_id=entry.id)
    return out
