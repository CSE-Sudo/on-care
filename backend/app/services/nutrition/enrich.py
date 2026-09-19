"""인식 결과(DietAnalysis)를 공공 식품영양성분 DB 값으로 보강.

각 음식을 food_nutrients 에 매칭해:
  - 매칭 O + 양(g) 확보 → DB 밀도 × 양 으로 교체. 인식기 탄단지가 남으면 "mixed"
  - 매칭 O + 양 없음    → 교체하지 않고 추정치 유지("estimate")
  - 매칭 X              → LLM 추정치 유지("estimate")
그 뒤 합계를 재계산한다. 엔진(gemini/yolo)과 무관하게 동작.

## 왜 양(g)이 필요한가

`food_nutrients` 값은 **100g 기준**이다. 원본 공공데이터가 전부 그 형태이고,
포장 단위(라지 피자 1,640g, 우유 1L 팩)로 1인분 환산하면 대표값이 3~5배까지
튀기 때문이다. 100g 기준이면 프랜차이즈 피자 4,692건도 서로 ±10% 안에 든다.

그래서 역할을 나눈다 — **밀도는 DB, 양은 사진.** 비전 모델은 "얼마나 있나" 는
잘 보지만 100g 당 나트륨은 모른다.

양을 못 얻었을 때 임의로 1인분을 가정하지는 않는다. 틀린 양으로 환산한 값은
`source="db"` 로 표시돼 사용자에게 "공공 DB 근거" 라는 더 높은 신뢰 신호를
주므로, 추정치를 그대로 두는 편이 낫다(matcher 의 폴백 원칙과 같다).
다만 `serving_size_g` 가 **알려진** 항목에 한해 그 값을 폴백으로 쓴다 —
식약처 「식품등의 표시기준」 1회 섭취참고량이나 가정식 분석 1인분처럼 근거가 있고,
100g 당 값과 같은 조리 상태의 무게인 경우다(#2102, `scripts/import_food_nutrients`·
`app/data/food_nutrients_seed` 설명). 근거가 없으면 비워 두어 여기서 추정치로 남는다.
"""
from __future__ import annotations

from sqlalchemy.orm import Session

from app.schemas.diet import DietAnalysis, RecognizedFood
from app.services.nutrition.matcher import match_in_rows
from app.services.nutrition.table import NutrientRow, load_rows


def _grams(food: RecognizedFood, match: NutrientRow) -> float | None:
    """환산에 쓸 양(g). 인식기 추정이 우선, 없으면 알려진 1회 섭취량."""
    if food.amount_g and food.amount_g > 0:
        return float(food.amount_g)
    serving = match.serving_size_g
    return float(serving) if serving and serving > 0 else None


def apply_match(food: RecognizedFood, match: NutrientRow, grams: float) -> None:
    """DB 행 × 양 → 그 음식의 영양. 보정과 이름 조회가 **같은 계산**을 쓴다.

    이름으로 찾는 `POST /diet/nutrition` 은 음식 하나짜리 보정과 같은 일이라,
    여기 말고 따로 곱셈을 두면 분석이 준 값과 이름으로 찾은 값이 갈린다 —
    같은 음식인데 화면 어디서 왔느냐에 따라 숫자가 달라진다. (#1896)
    """
    scale = grams / 100.0
    # 환산에 실제로 쓴 양을 그 음식에 남긴다(#1876). 인식기가 양을 못 준
    # 자리에서는 `serving_size_g` 로 환산하는데, 그 값을 적어 두지 않으면
    # "영양은 210g 기준인데 섭취량은 비어 있는" 기록이 되어 회원이 양을
    # 고쳐도 무엇에서 무엇으로 바뀌는 것인지 셀 수 없다.
    food.amount_g = grams
    # 칼로리·나트륨은 계약상 정수라 반올림이 맞다. 당류만 소수다(#296) —
    # 여기서 int 로 깎으면 컬럼·스키마·클라이언트까지 소수로 통일해 둔
    # 것이 이 한 줄에서 되돌려진다.
    food.calories = int(round((match.calories or 0) * scale))
    food.sodium_mg = int(round((match.sodium_mg or 0) * scale))
    food.sugar_g = float((match.sugar_g or 0) * scale)
    kept_recognizer_value = False
    for field in ("carbs_g", "protein_g", "fat_g"):
        db_value = getattr(match, field)
        if db_value is not None:
            setattr(food, field, float(db_value) * scale)
        elif getattr(food, field) is not None:
            kept_recognizer_value = True
    food.source = "mixed" if kept_recognizer_value else "db"


def lookup_by_name(
    db: Session, name: str, amount_g: float | None = None
) -> tuple[NutrientRow, RecognizedFood] | None:
    """이름으로 공공 DB 를 찾아 그 영양 한 벌을 만든다. 못 찾으면 None. (#1896)

    양을 정할 수 없으면(인식기 추정도 없고 `serving_size_g` 도 모르면) 찾은
    셈 치지 않는다 — 임의로 1인분을 가정하지 않는 것은 위 폴백 원칙과 같다.
    확정할 수 없는 숫자를 "공공 DB 근거" 로 내주는 것이 여기서 제일 나쁘다.
    """
    match = match_in_rows(load_rows(db), name)
    if match is None:
        return None
    food = RecognizedFood(name=name, amount_g=amount_g)
    grams = _grams(food, match)
    if grams is None:
        return None
    apply_match(food, match, grams)
    return match, food


def enrich_analysis(db: Session, analysis: DietAnalysis, enabled: bool = True) -> DietAnalysis:
    if not analysis.foods:
        return analysis

    if not enabled:
        for f in analysis.foods:
            if not f.source:
                f.source = "estimate"
        return analysis

    rows = load_rows(db)
    for food in analysis.foods:
        match = match_in_rows(rows, food.name)
        grams = _grams(food, match) if match is not None else None
        if match is None or grams is None:
            food.source = "estimate"
            continue

        apply_match(food, match, grams)

    return analysis.compute_totals()
