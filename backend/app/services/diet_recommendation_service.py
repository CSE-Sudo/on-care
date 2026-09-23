"""
홈 "AI 추천 식단" 추천 서비스 — 카탈로그 선택 방식.

파이프라인:
  1) 최근 식단·건강 목표에서 신호(nutrition signal)를 뽑는다.
  2) 규칙 점수로 카탈로그를 정렬한다(= LLM 없이도 성립하는 추천).
  3) LLM(Gemini)에게 카탈로그와 신호를 주고 순서·문구를 다듬게 한다.
  4) LLM 이 실패·지연·헛소리(카탈로그 밖 key)를 하면 2)의 결과로 되돌린다.

즉 **LLM 은 품질을 올리는 층이지 가용성의 전제가 아니다.** 어느 단계가 무너져도
화면은 항상 카드 5장을 받는다(근거가 아예 없으면 현재 홈 화면과 동일한 기본 순서).

응답에 문자열을 담지 않는 이유는 meal_catalog 모듈 주석 참고(로케일·에셋 계약).
"""
from __future__ import annotations

import json
import logging
import threading
import time
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout
from dataclasses import dataclass
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core import clock, metrics
from app.data import meal_catalog
from app.data.meal_catalog import CATALOG, DEFAULT_ORDER, RECOMMENDATION_COUNT, MealItem
from app.models.models import DietEntry, HealthProfile
from app.schemas.diet_api import DietRecommendationItem, DietRecommendationsResponse
from app.services.coach.llm import DEFAULT_THINKING_BUDGET, get_coach_llm

logger = logging.getLogger(__name__)


class LLMBusyError(RuntimeError):
    """LLM 동시 호출 한도가 차서 호출을 시도조차 하지 않았음을 알린다.

    "실패"와 구분해야 로그에서 장애와 포화를 헷갈리지 않는다.
    """

#: 신호를 뽑을 기간. 오늘 하루만 보면 아침 한 끼로 추천이 출렁이고, 너무 길게 보면
#: 최근 개선이 묻힌다.
LOOKBACK_DAYS = 3

#: 기본 일일 한도. 나트륨은 WHO 권고, 당류는 2025 한국인 영양소 섭취기준의 첨가당
#: 권고(총에너지 10% 이내)를 따른다. HealthProfile 에 개인 목표가 있으면 그쪽이 우선한다.
DEFAULT_SODIUM_LIMIT_MG = 2000
DEFAULT_SUGAR_LIMIT_G = 50
DEFAULT_CALORIE_LIMIT = 2000

#: 한도의 몇 %를 넘으면 "과다" 신호로 볼지. 1.0 은 경계에서 신호가 깜빡이므로 여유를 둔다.
_HIGH_RATIO = 0.9
#: 한도의 몇 % 미만이면 "부족" 신호로 볼지.
_LOW_RATIO = 0.6

#: LLM 응답을 기다리는 최대 시간(초). 홈 화면은 기본 카드를 먼저 그리므로 응답이
#: 늦어도 화면이 비지는 않지만, 요청 스레드를 오래 잡아두지 않도록 끊는다.
#: 아래 사고 예산과 함께 쓰면 실측 1~2초라 6초면 충분한 여유다.
LLM_TIMEOUT_SEC = 6.0

#: Gemini 사고 토큰 상한. 근거와 값은 `coach/llm.py` 로 승격했다 — 지연을 지배하는
#: 값이라 호출부마다 따로 두면 한쪽만 누락돼 조용히 느려진다(#579).
LLM_THINKING_BUDGET = DEFAULT_THINKING_BUDGET

#: 추천 캐시 TTL(초). 홈 진입마다 LLM 을 부르면 비용·지연이 커진다. 같은 사용자의
#: 같은 신호 조합이면 결과가 같으므로 짧게 캐시한다.
CACHE_TTL_SEC = 300

LLM_MAX_CONCURRENCY = 4

_executor = ThreadPoolExecutor(
    max_workers=LLM_MAX_CONCURRENCY, thread_name_prefix="diet-rec-llm"
)

#: 진행 중인 LLM 호출 수를 워커 수로 제한한다.
#:
#: `future.result(timeout=...)` 은 **기다리기를 포기할 뿐 작업을 취소하지 않는다.**
#: 그래서 느린 호출이 몰리면 워커 4개가 모두 묶이고, 이후 submit 은 무한 큐에 쌓인다.
#: 그 상태에서는 새 요청이 LLM 을 호출해 보지도 못한 채 큐에서 타임아웃까지 기다렸다가
#: 폴백한다 — 개인화는 조용히 사라지고 응답만 매번 느려진다.
#: 빈 자리가 없으면 기다리지 않고 곧장 규칙 폴백으로 내려간다.
_llm_slots = threading.BoundedSemaphore(LLM_MAX_CONCURRENCY)

#: 캐시 최대 항목 수. 넘으면 만료된 항목부터 정리한다. 만료를 읽을 때만 확인하면
#: 다시 조회되지 않는 키(지난 날짜·사라진 신호 조합)가 영영 남아 메모리가 단조 증가한다.
CACHE_MAX_ENTRIES = 1000

#: key -> (만료 시각, 응답). 단일 인스턴스/데모 기준. 다중 인스턴스면 Redis 로 교체.
_cache: dict[str, tuple[float, DietRecommendationsResponse]] = {}


def _cache_put(key: str, response: DietRecommendationsResponse) -> None:
    now = time.monotonic()
    if len(_cache) >= CACHE_MAX_ENTRIES:
        for expired in [k for k, (exp, _) in _cache.items() if exp <= now]:
            del _cache[expired]
    _cache[key] = (now + CACHE_TTL_SEC, response)


def clear_cache() -> None:
    """캐시 초기화(테스트 격리용)."""
    _cache.clear()


@dataclass
class NutritionContext:
    """추천 근거가 되는 최근 섭취 요약. `signals` 가 비면 개인화할 근거가 없다는 뜻."""

    days_with_data: int
    avg_sodium_mg: int
    avg_sugar_g: float
    avg_calories: int
    avg_protein_g: float
    sodium_limit_mg: int
    sugar_limit_g: int
    calorie_limit: int
    conditions: str
    goals: str
    signals: tuple[str, ...]

    @property
    def has_data(self) -> bool:
        return self.days_with_data > 0

    def fingerprint(self) -> str:
        """캐시 키의 일부.

        신호만 담으면 안 된다. 응답이 평균 나트륨 **수치**를 화면에 그대로 노출하므로,
        사용자가 식단을 새로 기록해 평균이 바뀌어도 신호가 그대로면 최대 TTL 동안 예전
        수치가 보인다(방금 입력한 값과 어긋나 보인다). 100mg 단위로 뭉뚱그려 키에 섞어
        수치가 의미 있게 바뀔 때만 다시 만든다.
        """
        signals = "|".join(self.signals) or "none"
        return f"{signals}:{self.avg_sodium_mg // 100}"

    def basis(self) -> str | None:
        """추천 근거 한 줄. 화면에 그대로 노출되므로 수치를 명시한다."""
        if not self.has_data:
            return None
        parts = [f"최근 {self.days_with_data}일 평균 나트륨 {self.avg_sodium_mg:,}mg"]
        if "sodium_high" in self.signals:
            parts.append(f"권장 {self.sodium_limit_mg:,}mg 초과")
        if "sugar_high" in self.signals:
            parts.append(f"당류 {self.avg_sugar_g:.0f}g(권장 {self.sugar_limit_g}g 초과)")
        if "protein_low" in self.signals:
            parts.append("단백질 부족")
        return " · ".join(parts)


def _load_profile(db: Session, user_id: str) -> HealthProfile | None:
    return db.scalar(select(HealthProfile).where(HealthProfile.user_id == user_id))


def build_context(db: Session, user_id: str, today: date | None = None) -> NutritionContext:
    """최근 LOOKBACK_DAYS 일의 식단 + 건강 목표에서 신호를 뽑는다.

    평균은 '기록이 있는 날' 기준이다. 기록이 없는 날을 0 으로 세면 하루만 기록한
    사용자의 평균이 실제보다 낮게 나와 과다 신호를 놓친다.
    """
    today = today or clock.today()
    start = (today - timedelta(days=LOOKBACK_DAYS - 1)).isoformat()
    end = today.isoformat()

    rows = db.scalars(
        select(DietEntry).where(
            DietEntry.user_id == user_id,
            DietEntry.date >= start,
            DietEntry.date <= end,
        )
    ).all()

    per_day: dict[str, dict[str, float]] = {}
    for r in rows:
        day = per_day.setdefault(
            r.date, {"sodium": 0.0, "sugar": 0.0, "calories": 0.0, "protein": 0.0}
        )
        day["sodium"] += r.sodium_mg
        day["sugar"] += r.sugar_g
        day["calories"] += r.total_calories
        day["protein"] += r.protein_g

    n = len(per_day)
    avg_sodium = int(sum(d["sodium"] for d in per_day.values()) / n) if n else 0
    avg_sugar = (sum(d["sugar"] for d in per_day.values()) / n) if n else 0.0
    avg_cal = int(sum(d["calories"] for d in per_day.values()) / n) if n else 0
    avg_protein = (sum(d["protein"] for d in per_day.values()) / n) if n else 0.0

    profile = _load_profile(db, user_id)
    sodium_limit = (profile.daily_sodium_mg if profile else None) or DEFAULT_SODIUM_LIMIT_MG
    sugar_limit = (profile.daily_sugar_g if profile else None) or DEFAULT_SUGAR_LIMIT_G
    calorie_limit = (profile.daily_calories if profile else None) or DEFAULT_CALORIE_LIMIT
    protein_goal = (profile.daily_protein_g if profile else None) or 0

    signals: list[str] = []
    if n:
        if avg_sodium >= sodium_limit * _HIGH_RATIO:
            signals.append("sodium_high")
        if avg_sugar >= sugar_limit * _HIGH_RATIO:
            signals.append("sugar_high")
        if avg_cal >= calorie_limit * _HIGH_RATIO:
            signals.append("calorie_high")
        elif avg_cal and avg_cal <= calorie_limit * _LOW_RATIO:
            signals.append("calorie_low")
        if protein_goal and avg_protein <= protein_goal * _LOW_RATIO:
            signals.append("protein_low")

    return NutritionContext(
        days_with_data=n,
        avg_sodium_mg=avg_sodium,
        avg_sugar_g=avg_sugar,
        avg_calories=avg_cal,
        avg_protein_g=avg_protein,
        sodium_limit_mg=sodium_limit,
        sugar_limit_g=sugar_limit,
        calorie_limit=calorie_limit,
        conditions=(profile.conditions if profile else "") or "",
        goals=(profile.goals if profile else "") or "",
        signals=tuple(signals),
    )


def _rule_rank(ctx: NutritionContext) -> list[MealItem]:
    """신호와 `good_for` 가 겹치는 만큼 점수를 준다.

    동점은 카탈로그 기본 순서를 유지한다(= 현재 화면 순서). 신호가 없으면 전원 0점
    이라 결과가 정확히 DEFAULT_ORDER 가 된다.
    """
    active = set(ctx.signals)

    def score(item: MealItem) -> int:
        return len(active & set(item.good_for))

    return sorted(CATALOG, key=lambda i: (-score(i), DEFAULT_ORDER.index(i.key)))


def _fallback_items(ctx: NutritionContext) -> list[DietRecommendationItem]:
    return [
        DietRecommendationItem(key=item.key, reason_key=item.default_reason)
        for item in _rule_rank(ctx)
    ]


def _response(
    ctx: NutritionContext,
    items: list[DietRecommendationItem],
    *,
    personalized: bool,
    source: str,
) -> DietRecommendationsResponse:
    """응답 조립 — 근거를 문장과 수치 양쪽으로 싣는다.

    `basis` 는 서버가 조립한 한국어 문장이라 영어 로케일에 그대로 못 쓴다. 그래서
    앱이 직접 문구를 만들 수 있도록 수치도 함께 준다(요리명·이유를 key 로 주고받는
    것과 같은 이유).
    """
    return DietRecommendationsResponse(
        items=items,
        basis=ctx.basis(),
        personalized=personalized,
        source=source,
        days_with_data=ctx.days_with_data,
        avg_sodium_mg=ctx.avg_sodium_mg,
        sodium_limit_mg=ctx.sodium_limit_mg,
    )


def _build_prompt(ctx: NutritionContext) -> tuple[str, str]:
    catalog_lines = "\n".join(
        f"- {i.key}: 태그={'/'.join(i.tags)}, {i.calories}kcal, "
        f"나트륨 {i.sodium_mg}mg, 당류 {i.sugar_g}g, 단백질 {i.protein_g}g, 식이섬유 {i.fiber_g}g"
        for i in CATALOG
    )
    # reason_key 는 LLM 에게 맡기지 않는다. 실측에서 순서는 잘 잡으면서 reason_key 를
    # 엉뚱하게 골랐다(예: salmon 에 fiber 를 주고 본문엔 단백질 이야기). reason_key 는
    # reason_text 가 없을 때 화면에 뜨는 값이라 틀리면 그대로 오답이 보인다. 요리↔기본
    # 이유 짝은 카탈로그에 고정돼 있으므로 서버가 붙이고, LLM 은 순서와 개인화 문구만
    # 담당한다(출력 토큰이 줄어 응답도 빨라진다).
    system = (
        "너는 한국인 식단을 코칭하는 영양 코치다. 사용자의 최근 섭취 요약을 보고 "
        "**주어진 카탈로그 안에서만** 오늘 추천할 식단의 우선순위를 정한다.\n"
        "규칙:\n"
        "1. 카탈로그에 없는 요리를 지어내지 마라. key 는 반드시 목록에 있는 값이어야 한다.\n"
        f"2. 카탈로그의 {RECOMMENDATION_COUNT}개 key 를 모두, 중복 없이, 추천 순서대로 나열한다.\n"
        "3. reason_text 는 사용자의 수치를 근거로 든 한 문장(공백 포함 24자 이내)이다. "
        "카드에 들어가므로 짧아야 한다. 근거가 약하면 생략(null)한다.\n"
        "4. 의학적 진단·치료를 단정하지 마라. 식단 제안에 그친다.\n"
        'JSON 만 출력한다: {"items":[{"key":"...","reason_text":"..."}]}'
    )
    user = (
        f"[카탈로그]\n{catalog_lines}\n\n"
        f"[최근 {ctx.days_with_data}일 평균 섭취]\n"
        f"- 나트륨 {ctx.avg_sodium_mg}mg (권장 {ctx.sodium_limit_mg}mg)\n"
        f"- 당류 {ctx.avg_sugar_g:.1f}g (권장 {ctx.sugar_limit_g}g)\n"
        f"- 칼로리 {ctx.avg_calories}kcal (권장 {ctx.calorie_limit}kcal)\n"
        f"- 단백질 {ctx.avg_protein_g:.1f}g\n"
        f"- 감지된 신호: {', '.join(ctx.signals) or '없음'}\n"
        f"- 건강 상태: {ctx.conditions or '정보 없음'}\n"
        f"- 목표: {ctx.goals or '정보 없음'}\n"
    )
    return system, user


def _strip_code_fence(text: str) -> str:
    """```json ... ``` 로 감싸 오는 경우가 있어 벗겨낸다."""
    t = text.strip()
    if not t.startswith("```"):
        return t
    body = t.split("\n", 1)[1] if "\n" in t else ""
    return body.rsplit("```", 1)[0].strip()


def _parse_llm_items(raw: str, ctx: NutritionContext) -> list[DietRecommendationItem]:
    """LLM 출력 → 검증된 추천 목록.

    카탈로그 밖 key 와 중복은 버린다. `reason_key` 는 LLM 값을 쓰지 않고 카탈로그
    기본값을 붙인다(프롬프트 주석 참고). 개수가 모자라면 규칙 순서로 채워 항상
    RECOMMENDATION_COUNT 장을 만든다(카드 수가 흔들리면 화면이 바뀐다).
    파싱 자체가 실패하면 예외를 올려 호출부가 규칙 폴백으로 내려가게 한다.
    """
    data = json.loads(_strip_code_fence(raw))
    items_raw = data["items"] if isinstance(data, dict) else data
    if not isinstance(items_raw, list):
        raise ValueError("items 가 배열이 아님")

    picked: list[DietRecommendationItem] = []
    seen: set[str] = set()
    for row in items_raw:
        if not isinstance(row, dict):
            continue
        key = str(row.get("key", "")).strip()
        item = meal_catalog.get(key)
        if item is None or key in seen:
            continue
        text = row.get("reason_text")
        reason_text = str(text).strip() if isinstance(text, str) and text.strip() else None
        picked.append(
            DietRecommendationItem(
                key=key, reason_key=item.default_reason, reason_text=reason_text
            )
        )
        seen.add(key)

    if not picked:
        raise ValueError("유효한 key 가 하나도 없음")

    for fb in _fallback_items(ctx):
        if len(picked) >= RECOMMENDATION_COUNT:
            break
        if fb.key not in seen:
            picked.append(fb)
            seen.add(fb.key)
    return picked[:RECOMMENDATION_COUNT]


def _llm_items(ctx: NutritionContext) -> list[DietRecommendationItem]:
    """LLM 호출 + 타임아웃. 실패는 호출부가 잡아 규칙 폴백으로 내린다.

    빈 워커가 없으면 큐에서 기다리지 않고 즉시 실패시킨다(_llm_slots 주석 참고).
    기다려 봐야 타임아웃이고, 그동안 요청 스레드만 붙잡아 두기 때문이다.
    """
    if not _llm_slots.acquire(blocking=False):
        raise LLMBusyError("LLM 동시 호출 한도 초과 — 규칙 폴백")

    system, user = _build_prompt(ctx)

    def _call():
        try:
            return get_coach_llm().generate(
                system, user, json_mode=True, thinking_budget=LLM_THINKING_BUDGET
            )
        finally:
            # 타임아웃으로 호출부가 떠난 뒤라도 작업이 끝나면 자리를 반드시 돌려준다.
            _llm_slots.release()

    future = _executor.submit(_call)
    result = future.result(timeout=LLM_TIMEOUT_SEC)
    return _parse_llm_items(result.text, ctx)


def build_recommendations(
    db: Session,
    user_id: str,
    *,
    use_llm: bool = True,
    today: date | None = None,
) -> DietRecommendationsResponse:
    """홈 추천 식단. 어떤 실패에도 카드 RECOMMENDATION_COUNT 장을 반환한다."""
    # 조회 구간과 캐시 키가 같은 날짜를 쓰도록 여기서 한 번만 확정한다 — 각자
    # 시계를 읽으면 KST 자정 사이에 어제 데이터를 오늘 키로 캐싱할 수 있다.
    effective_today = today or clock.today()
    ctx = build_context(db, user_id, effective_today)

    # 근거가 없으면 LLM 을 부를 이유가 없다. 신규 가입자는 여기서 현재 홈 화면과
    # 동일한 기본 순서를 받는다.
    if not ctx.has_data or not ctx.signals:
        # `rules` 가 아니라 별도 라벨을 쓴다 — 여기는 AI 가 실패한 게 아니라 부를
        # 이유가 없었던 경우다. 같은 칸에 세면 신규 가입이 몰릴 때 폴백률이 치솟아
        # AI 가 죽은 것처럼 보인다. `fallback` 카운터는 올리지 않는다(#583).
        metrics.incr("diet_recommendations.generated", by="no_data")
        return _response(ctx, _fallback_items(ctx), personalized=False, source="fallback")

    # use_llm 을 키에 넣지 않으면 규칙 응답이 LLM 요청에 재사용된다(디버깅·비용 절감용
    # 호출 한 번이 그 사용자의 추천을 TTL 동안 규칙 결과로 고정해 버린다).
    cache_key = (
        f"{user_id}:{effective_today.isoformat()}:"
        f"{ctx.fingerprint()}:llm={use_llm}"
    )
    hit = _cache.get(cache_key)
    if hit and hit[0] > time.monotonic():
        return hit[1]

    # 계측은 캐시 미스 이후에만 센다(#583) — 세는 대상은 '요청 수'가 아니라 '생성
    # 시도'다. 캐시 적중까지 세면 TTL 길이가 폴백률을 흔든다.
    if use_llm:
        try:
            response = _response(ctx, _llm_items(ctx), personalized=True, source="llm")
            metrics.incr("diet_recommendations.generated", by="llm")
            _cache_put(cache_key, response)
            return response
        except LLMBusyError:
            metrics.incr("diet_recommendations.fallback", reason="busy")
            logger.info("diet recommendation LLM 포화 — 규칙 폴백")
        except FutureTimeout:
            metrics.incr("diet_recommendations.fallback", reason="timeout")
            logger.warning("diet recommendation LLM timeout (%.1fs) — 규칙 폴백", LLM_TIMEOUT_SEC)
        except Exception:  # noqa: BLE001 - LLM 장애 종류와 무관하게 화면은 떠야 한다
            metrics.incr("diet_recommendations.fallback", reason="error")
            logger.warning("diet recommendation LLM 실패 — 규칙 폴백", exc_info=True)

    # 규칙 폴백도 신호를 반영한 진짜 추천이다(예: 나트륨 과다 → 저나트륨 상위).
    metrics.incr("diet_recommendations.generated", by="rules")
    response = _response(ctx, _fallback_items(ctx), personalized=True, source="rules")
    _cache_put(cache_key, response)
    return response
