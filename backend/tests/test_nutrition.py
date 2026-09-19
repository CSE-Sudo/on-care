"""공공 식품영양성분 DB 매핑.

- 정규화/후보 매칭은 순수(로컬 실행).
- 시드 조회 + 보강(enrich)은 DB 필요(로컬 skip, CI 실행).
"""
from __future__ import annotations

import importlib.util
from functools import lru_cache
from pathlib import Path
from types import SimpleNamespace

import pytest

from app.services.nutrition.matcher import match_in_rows, normalize


# ---------- 순수 유닛 ----------

def test_normalize_strips_space_punct_digits():
    assert normalize("김치  찌개!!") == "김치찌개"
    assert normalize("공기밥 1") == "공기밥"
    assert normalize("후라이드 치킨 (1개)") == "후라이드치킨개"  # 숫자만 제거, 단위어는 남음
    assert normalize("   ") == ""


def _rows(*names):
    return [SimpleNamespace(name_norm=normalize(n)) for n in names]


def test_match_exact_and_contained():
    rows = _rows("김치찌개", "김치", "된장찌개")
    # 정확 일치
    assert match_in_rows(rows, "김치찌개").name_norm == "김치찌개"
    # 서술형 질의에 음식명 포함 → 가장 긴 이름(김치찌개 > 김치)
    assert match_in_rows(rows, "점심에 먹은 김치찌개 1인분").name_norm == "김치찌개"
    # '김치'는 정확 일치가 우선
    assert match_in_rows(rows, "김치").name_norm == "김치"


def test_match_none_when_unknown_or_ambiguous():
    rows = _rows("된장찌개", "된장국")
    assert match_in_rows(rows, "외계인 수프") is None          # 미매칭
    assert match_in_rows(rows, "된장") is None                 # 여러 이름의 부분 → 모호 → 폴백


# ---------- 머리 일치·별칭 (#2096) ----------

def test_single_char_rows_match_only_exactly():
    """한 글자 행이 긴 이름의 일부로 걸리면 `오트밀` 이 밀가루 값을 받는다."""
    rows = _rows("밀", "무", "조", "마")
    assert match_in_rows(rows, "밀").name_norm == "밀"
    for name in ("오트밀", "통밀빵", "오이무침", "갈치조림", "고구마"):
        assert match_in_rows(rows, name) is None, name


def test_contained_name_must_be_the_last_word():
    """한국어 음식 이름은 끝말이 음식을 정한다 — `소금빵` 은 빵이지 소금이 아니다."""
    rows = _rows("소금", "보리", "치킨", "비빔밥", "케이크")
    assert match_in_rows(rows, "야채비빔밥").name_norm == "비빔밥"
    assert match_in_rows(rows, "초코 케이크").name_norm == "케이크"
    for name in ("소금빵", "보리차", "치킨무"):
        assert match_in_rows(rows, name) is None, name


def test_unique_partial_must_be_the_last_word():
    """질의가 표 이름의 앞부분이면 다른 음식이다 — 닭가슴살 ≠ 닭가슴살 샐러드."""
    rows = _rows("닭가슴살 샐러드", "토마토케첩")
    assert match_in_rows(rows, "닭가슴살") is None
    assert match_in_rows(rows, "케첩").name_norm == "토마토케첩"


def test_quantity_words_are_not_part_of_the_name():
    rows = _rows("소주", "케이크", "피자", "메추리알", "된장")
    assert match_in_rows(rows, "소주 1병").name_norm == "소주"
    assert match_in_rows(rows, "초코 케이크 한 조각").name_norm == "케이크"
    assert match_in_rows(rows, "피자 (1조각)").name_norm == "피자"
    assert match_in_rows(rows, "메추리알 5알").name_norm == "메추리알"
    # 앞에 수가 없으면 이름의 일부다 — `된장` 의 `장` 을 떼지 않는다.
    assert match_in_rows(rows, "된장").name_norm == "된장"


def test_trailing_note_is_not_the_name():
    """괄호 설명을 떼지 않으면 괄호 안(`돼지고기`)이 이름의 끝이 된다."""
    rows = _rows("김치찌개", "돼지고기")
    assert match_in_rows(rows, "김치찌개(돼지고기)").name_norm == "김치찌개"


def test_aliases_reach_rows_by_common_names():
    rows = _rows("공기밥", "스크램블드에그", "농후발효유", "그래놀라 토핑")
    for name in ("밥", "밥 1공기", "밥 반공기", "공깃밥", "흰 밥"):
        assert match_in_rows(rows, name).name_norm == "공기밥", name
    for name in ("스크램블 에그", "계란 스크램블"):
        assert match_in_rows(rows, name).name_norm == "스크램블드에그", name
    assert match_in_rows(rows, "딸기 요거트").name_norm == "농후발효유"
    assert match_in_rows(rows, "그래놀라").name_norm == "그래놀라토핑"
    # 한 글자 별칭 `밥` 도 정확 일치로만 붙는다 — 비빔밥은 공기밥이 아니다.
    assert match_in_rows(rows, "비빔밥") is None


def test_alias_is_ignored_when_its_row_is_missing():
    """별칭 대상이 없는 DB(마이그레이션 전)에서는 별칭이 없는 것과 같다."""
    assert match_in_rows(_rows("쌀밥"), "밥") is None


def test_egg_spelling_variant():
    """공공 표준은 `달걀`, 사람과 인식기는 `계란` 을 더 많이 쓴다."""
    rows = _rows("달걀", "달걀국", "달걀말이")
    assert match_in_rows(rows, "삶은 계란").name_norm == "달걀"
    assert match_in_rows(rows, "계란 2개").name_norm == "달걀"
    assert match_in_rows(rows, "계란국").name_norm == "달걀국"
    assert match_in_rows(rows, "계란말이").name_norm == "달걀말이"


# ---------- 시드와 같은 행 구성 (#2096) ----------

@lru_cache(maxsize=1)
def _seed_rows():
    """`init_db._seed_food_nutrients` 가 만드는 것과 같은 행 — DB 없이."""
    from app.data.food_nutrients_seed import FOOD_NUTRIENTS
    from app.db.init_db import _curated_per_100g, _public_food_rows
    from app.services.nutrition.table import NutrientRow

    rows, seen = [], set()
    for i, item in enumerate([*_curated_per_100g(FOOD_NUTRIENTS), *_public_food_rows()]):
        norm = normalize(item["name"])
        if not norm or norm in seen:
            continue
        seen.add(norm)
        rows.append(NutrientRow(
            id=i, name=item["name"], name_norm=norm, category=item.get("category", ""),
            serving_size_g=item.get("serving_size_g"), calories=item.get("calories", 0),
            sodium_mg=item.get("sodium_mg", 0), sugar_g=item.get("sugar_g", 0),
            carbs_g=item.get("carbs_g"), protein_g=item.get("protein_g"),
            fat_g=item.get("fat_g"),
        ))
    return tuple(rows)


@pytest.mark.parametrize(("name", "expected"), [
    ("오트밀", "오트밀"),
    ("밥", "공기밥"),
    ("스크램블 에그", "스크램블드에그"),
    ("그릭 요거트", "그릭 요거트"),
    ("닭가슴살", "닭가슴살"),
    ("삶은 계란", "달걀"),
    ("요거트", "농후발효유"),
    ("소주 1병", "소주"),
    ("초코 케이크 한 조각", "케이크"),
    ("야채비빔밥", "비빔밥"),
    # 스텁 인식기 이름 — tests/test_diet.py 의 395kcal·탄단지 59/9/14 가 여기에 기댄다.
    ("요거트 아이스크림", "요거트 아이스크림"),
    ("과일 토핑", "과일 토핑"),
    ("그래놀라 토핑", "그래놀라 토핑"),
])
def test_seed_rows_match_common_names(name, expected):
    assert match_in_rows(_seed_rows(), name).name == expected


@pytest.mark.parametrize("name", ["오트밀 쿠키", "통밀빵"])
def test_seed_rows_do_not_read_oat_as_wheat(name):
    """#2096 전에는 둘 다 `밀`(밀가루 334kcal/100g)에 붙었다. 모르면 추정치를 둔다."""
    assert match_in_rows(_seed_rows(), name) is None


def test_oatmeal_is_not_wheat_flour():
    """#2096: 오트밀 250g 이 `밀` 로 읽혀 835kcal·탄수화물 185g 이 나왔다."""
    from app.schemas.diet import RecognizedFood
    from app.services.nutrition.enrich import apply_match

    food = RecognizedFood(name="오트밀", amount_g=250)
    apply_match(food, match_in_rows(_seed_rows(), "오트밀"), 250)
    assert food.calories == 178
    assert (food.carbs_g, food.protein_g, food.fat_g) == pytest.approx((30.0, 6.35, 3.8))
    assert food.source == "db"


def test_curated_rows_carry_macros_that_add_up_to_calories():
    """큐레이션 행이 탄·단·지를 비우면 인식기가 값을 안 준 음식은 0 이 된다.

    탄·단·지는 참조 행의 비율을 큐레이션 칼로리에 맞춰 환산했으므로, 4·4·9 로
    다시 셈하면 칼로리와 맞아야 한다.
    """
    from app.data.food_nutrients_seed import FOOD_NUTRIENTS
    from app.db.init_db import _curated_per_100g

    for row in _curated_per_100g(FOOD_NUTRIENTS):
        macros = (row.get("carbs_g"), row.get("protein_g"), row.get("fat_g"))
        assert None not in macros, row["name"]
        if row["calories"] < 20:   # 아메리카노 — 열량이 탄·단·지에서 오지 않는다
            continue
        atwater = macros[0] * 4 + macros[1] * 4 + macros[2] * 9
        assert atwater == pytest.approx(row["calories"], rel=0.12), row["name"]


def test_aliases_point_at_seeded_rows():
    """대상이 없는 별칭은 조용히 무시되므로, 오타가 나도 아무도 모른다."""
    from app.services.nutrition.matcher import ALIASES

    names = {r.name_norm for r in _seed_rows()}
    for alias, target in ALIASES.items():
        assert normalize(target) in names, target
        # 표 이름과 같으면 별칭이 아니라 그 행이 붙는다.
        assert normalize(alias) not in names, alias


# ---------- 이미 떠 있는 DB 반영 (#2096 마이그레이션) ----------

def _migration_0075():
    path = (
        Path(__file__).resolve().parents[1]
        / "migrations" / "versions" / "0075_food_nutrient_macros.py"
    )
    spec = importlib.util.spec_from_file_location("migration_0075", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_migration_carries_the_seed_values():
    """새로 만든 DB(시드)와 이미 떠 있는 DB(마이그레이션)의 숫자가 같아야 한다."""
    from app.data.food_nutrients_seed import FOOD_NUTRIENTS
    from app.db.init_db import _curated_per_100g

    migration = _migration_0075()
    macros = {m[0]: m[1:] for m in migration.MACROS}
    new_rows = {r["name_norm"]: r for r in migration.NEW_ROWS}
    had_macros = {"요거트아이스크림", "과일토핑", "그래놀라토핑"}

    for row in _curated_per_100g(FOOD_NUTRIENTS):
        norm = normalize(row["name"])
        if norm in had_macros:
            continue
        if norm in new_rows:
            new = new_rows.pop(norm)
            assert {k: new[k] for k in row} == row, row["name"]
        else:
            assert macros.pop(norm) == (
                row["calories"], row["carbs_g"], row["protein_g"], row["fat_g"]
            ), row["name"]
    assert not macros and not new_rows       # 시드에 없는 값이 남지 않는다


def test_migration_fills_an_already_seeded_table(db_session):
    """시드는 빈 표에만 들어가므로 떠 있는 DB 는 마이그레이션으로 채워진다."""
    from sqlalchemy import text

    migration = _migration_0075()
    conn = db_session.connection()

    def rows():
        return {
            r.name_norm: r
            for r in conn.execute(text(
                "SELECT name_norm, calories, carbs_g, protein_g, fat_g FROM food_nutrients "
                "WHERE name_norm IN ('공기밥', '김밥', '오트밀', '그릭요거트', '닭가슴살')"
            ))
        }

    # #2096 이전 시드 상태: 큐레이션 탄·단·지가 비었고 새 항목이 없다. 김밥은 누가
    # 칼로리를 고쳐 둔 행 — 이 칼로리에 맞춘 탄·단·지가 아니므로 채우면 안 된다.
    conn.execute(text(
        "UPDATE food_nutrients SET carbs_g = NULL, protein_g = NULL, fat_g = NULL "
        "WHERE name_norm IN ('공기밥', '김밥')"
    ))
    conn.execute(text("UPDATE food_nutrients SET calories = 999 WHERE name_norm = '김밥'"))
    conn.execute(text(
        "DELETE FROM food_nutrients WHERE name_norm IN ('오트밀', '그릭요거트', '닭가슴살')"
    ))
    try:
        migration.fill(conn)
        migration.fill(conn)                 # 두 번 돌려도 같다
        after = rows()
        assert (after["공기밥"].carbs_g, after["공기밥"].protein_g) == pytest.approx((33.1, 2.81))
        assert after["김밥"].carbs_g is None
        assert after["오트밀"].calories == pytest.approx(71.0)
        assert after["닭가슴살"].protein_g == pytest.approx(28.0)
        assert conn.execute(text(
            "SELECT count(*) FROM food_nutrients WHERE name_norm = '오트밀'"
        )).scalar() == 1

        migration.unfill(conn)
        after = rows()
        assert after["공기밥"].carbs_g is None
        assert "오트밀" not in after and "그릭요거트" not in after
    finally:
        db_session.rollback()


def test_migration_leaves_an_empty_table_to_the_seed(db_session):
    """빈 표에 한 행이라도 넣으면 시드가 찼다고 보고 공공 표준 2천여 행을 건너뛴다."""
    from sqlalchemy import text

    migration = _migration_0075()
    conn = db_session.connection()
    conn.execute(text("DELETE FROM food_nutrients"))
    try:
        migration.fill(conn)
        assert conn.execute(text("SELECT count(*) FROM food_nutrients")).scalar() == 0
    finally:
        db_session.rollback()


# ---------- DB (CI) ----------

def test_food_nutrients_seeded_and_lookup(db_session):
    from app.services.nutrition.matcher import match_food

    m = match_food(db_session, "김치찌개")
    assert m is not None
    # 값은 100g 기준이다(큐레이션 1,200mg/400g → 300). 1인분 절대값이 아니다.
    assert 100 < m.sodium_mg < 500
    # 서술형 이름도 매칭
    assert match_food(db_session, "오늘 저녁 김치찌개").name_norm == "김치찌개"


def test_enrich_overrides_matched_keeps_unmatched(db_session):
    from app.schemas.diet import DietAnalysis, RecognizedFood
    from app.services.nutrition.enrich import enrich_analysis

    analysis = DietAnalysis(engine="gemini", foods=[
        RecognizedFood(name="김치찌개", calories=999, sodium_mg=50, sugar_g=99),  # LLM 엉터리 추정
        RecognizedFood(name="외계인수프", calories=123, sodium_mg=45, sugar_g=6),  # 미매칭
    ])
    enrich_analysis(db_session, analysis)

    matched, unmatched = analysis.foods
    assert matched.source == "db" and matched.sodium_mg > 500      # DB 신뢰값으로 교체
    assert matched.calories != 999
    assert unmatched.source == "estimate" and unmatched.sodium_mg == 45  # 추정 유지
    # 합계 재계산
    assert analysis.total_sodium_mg == matched.sodium_mg + unmatched.sodium_mg
    assert analysis.total_calories == matched.calories + unmatched.calories


def _raw(name, rep, origin, weight, kcal, na, sugar, cat="찌개류"):
    return {
        "식품명": name, "대표식품명": rep, "식품기원명": origin,
        "식품중량": weight, "식품대분류명": cat,
        "에너지(kcal)": kcal, "나트륨(mg)": na, "당류(g)": sugar,
        "탄수화물(g)": "", "단백질(g)": "", "지방(g)": "",
    }


def test_import_keeps_the_100g_basis_untouched():
    """원본이 100g 기준이므로 환산하지 않는다 — 손실도 추측도 없다."""
    from scripts.import_food_nutrients import aggregate

    out = aggregate([_raw("김치찌개_돼지", "김치찌개", "가정식(분석 함량)", "300g", "31", "445", "0.04")], "음식")
    assert out[0]["calories"] == 31.0        # 300g 로 환산하지 않는다
    assert out[0]["sodium_mg"] == 445.0
    assert out[0]["sugar_g"] == 0.04         # 소수 보존


def test_import_keeps_franchise_rows_for_density():
    """포장 크기는 100g 당 값에 영향을 주지 않으므로 제외할 이유가 없다."""
    from scripts.import_food_nutrients import aggregate

    rows = [
        _raw("피자_라지", "피자", "외식(프랜차이즈 등 업체 제공 영양정", "1640g", "252", "416", "3.7"),
        _raw("피자_급식", "피자", "초등학교급식(재료량 기반 산출 함량)", "200g", "254", "420", "3.5"),
    ]
    out = aggregate(rows, "음식")
    assert out[0]["sample_count"] == 2       # 프랜차이즈도 표본에 든다
    assert out[0]["calories"] == 253.0       # 두 값의 중앙


def test_import_serving_hint_ignores_franchise_packaging():
    """1회 섭취량 힌트에는 판매 포장(라지 피자 한 판)을 쓰지 않는다."""
    from scripts.import_food_nutrients import aggregate

    rows = [
        _raw("피자_라지", "피자", "외식(프랜차이즈 등 업체 제공 영양정", "1640g", "252", "416", "3.7"),
        _raw("피자_급식", "피자", "초등학교급식(재료량 기반 산출 함량)", "200g", "254", "420", "3.5"),
    ]
    assert aggregate(rows, "음식")[0]["serving_size_g"] == 200.0


def test_import_leaves_serving_blank_when_unknown():
    """식품중량이 없는 데이터셋(원재료성식품)은 힌트를 비워 둔다 — 추측하지 않는다."""
    from scripts.import_food_nutrients import aggregate

    out = aggregate([_raw("사과", "사과", "원재료", "", "52", "1", "10.4")], "원재료성식품")
    assert out[0]["serving_size_g"] is None
    assert out[0]["calories"] == 52.0        # 100g 기준 값은 그대로 쓸 수 있다


def test_import_uses_median_not_mean():
    """이상치 한 건이 대표값을 끌고 가면 안 된다."""
    from scripts.import_food_nutrients import aggregate

    rows = [
        _raw(f"국_{i}", "된장국", "가정식(분석 함량)", "100g", kcal, "100", "1")
        for i, kcal in enumerate(["10", "20", "900"])
    ]
    assert aggregate(rows, "음식")[0]["calories"] == 20.0     # 평균이면 310


def test_import_skips_rows_without_energy():
    """보정 값으로 쓸 수 없는 행은 버린다."""
    from scripts.import_food_nutrients import aggregate

    assert aggregate([_raw("열량없음", "열량없음", "가정식(분석 함량)", "300g", "", "100", "1")], "음식") == []


# ---------- 양(g) 기반 보정 (DB) ----------

def test_enrich_scales_by_estimated_amount(db_session):
    """같은 음식이라도 사진에 담긴 양에 비례해야 한다."""
    from app.schemas.diet import DietAnalysis, RecognizedFood
    from app.services.nutrition.enrich import enrich_analysis

    def kcal_for(grams):
        a = DietAnalysis(engine="g", foods=[RecognizedFood(name="김치찌개", amount_g=grams)])
        enrich_analysis(db_session, a)
        return a.foods[0]

    small, large = kcal_for(200), kcal_for(800)
    assert small.source == "db" and large.source == "db"
    assert large.calories == small.calories * 4
    assert large.sodium_mg == small.sodium_mg * 4


def test_enrich_falls_back_to_known_serving_when_amount_missing(db_session):
    """양을 못 얻으면 알려진 1회 섭취량으로만 환산한다."""
    from app.schemas.diet import DietAnalysis, RecognizedFood
    from app.services.nutrition.enrich import enrich_analysis

    a = DietAnalysis(engine="g", foods=[RecognizedFood(name="김치찌개", calories=999)])
    enrich_analysis(db_session, a)
    assert a.foods[0].source == "db"
    assert a.foods[0].calories != 999


def test_enrich_keeps_estimate_when_amount_and_serving_unknown(db_session):
    """양도 1회 섭취량도 없으면 임의로 가정하지 않는다.

    틀린 양으로 환산한 값은 source="db" 로 표시돼 사용자에게 더 높은 신뢰
    신호를 준다 — 추정치를 그대로 두는 편이 낫다.
    """
    from app.models.models import FoodNutrient
    from app.schemas.diet import DietAnalysis, RecognizedFood
    from app.services.nutrition.enrich import enrich_analysis
    from app.services.nutrition.matcher import normalize

    db_session.add(FoodNutrient(
        name="양모르는음식", name_norm=normalize("양모르는음식"),
        calories=100, sodium_mg=10, sugar_g=1, serving_size_g=None,
    ))
    db_session.commit()

    a = DietAnalysis(engine="g", foods=[RecognizedFood(name="양모르는음식", calories=777)])
    enrich_analysis(db_session, a)
    assert a.foods[0].source == "estimate"
    assert a.foods[0].calories == 777


def test_enrich_keeps_fractional_sugar(db_session):
    """#296 회귀: 보정이 당류를 int 로 깎으면 안 된다."""
    from app.models.models import FoodNutrient
    from app.schemas.diet import DietAnalysis, RecognizedFood
    from app.services.nutrition.enrich import enrich_analysis
    from app.services.nutrition.matcher import normalize

    db_session.add(FoodNutrient(
        name="소수당류식품", name_norm=normalize("소수당류식품"),
        calories=100, sodium_mg=10, sugar_g=8.5, serving_size_g=100,
    ))
    db_session.commit()

    a = DietAnalysis(engine="g", foods=[RecognizedFood(name="소수당류식품", amount_g=100)])
    enrich_analysis(db_session, a)
    assert a.foods[0].sugar_g == 8.5      # 예전에는 round(8.5) → 8


def test_curated_seed_wins_over_public_data(db_session):
    """큐레이션 40종은 고혈압·당뇨 관점으로 따로 검증한 값이라 우선한다."""
    from app.services.nutrition.matcher import match_food

    ramen = match_food(db_session, "라면")
    assert ramen is not None
    # 큐레이션 1,800mg/550g → 100g 당 327.3
    assert round(ramen.sodium_mg, 1) == 327.3
    assert match_food(db_session, "가공우유") is not None   # 가공식품 데이터셋


def test_import_reads_weight_units_explicitly():
    """단위를 무시하고 앞 숫자만 취하면 모르는 단위가 조용히 그램이 된다."""
    from scripts.import_food_nutrients import _weight_g

    assert _weight_g("300g") == 300.0
    assert _weight_g("201.7") == 201.7        # 무단위는 그램(원본 표기)
    assert _weight_g("2kg") == 2000.0
    # ml·L 은 밀도 1.0 가정 — 국물·음료라 대부분 물이다. 제외하면 김치찌개처럼
    # 100ml 기준으로 등록된 한식이 1회 섭취량 힌트를 통째로 잃는다.
    assert _weight_g("350ml") == 350.0
    assert _weight_g("1L") == 1000.0
    assert _weight_g("1000m") == 1000.0       # 원본에 실재하는 ml 절단 표기
    # 모르는 단위는 그램으로 쓰지 않는다.
    assert _weight_g("12oz") is None
    assert _weight_g("abc") is None
    assert _weight_g("6000g") is None         # 대형 포장은 1인분 힌트가 못 된다


# ---------- 원본 파일 읽기 (#2100) ----------

def _write_xlsx(path, rows, *, inline_first_row=False):
    """최소 구성의 xlsx. 첫 행은 인라인 문자열로, 나머지 문자열은 공유 문자열로 적는다."""
    import zipfile

    shared: list[str] = []
    sheet_rows = []
    for r, row in enumerate(rows, start=1):
        cells = []
        for c, value in enumerate(row):
            if value == "":
                continue                      # 빈 셀은 적지 않는다 — 열 주소로 자리를 잡아야 한다
            ref = f"{chr(65 + c)}{r}"
            if isinstance(value, (int, float)):
                cells.append(f'<c r="{ref}"><v>{value}</v></c>')
            elif r == 1 and inline_first_row:
                cells.append(f'<c r="{ref}" t="inlineStr"><is><t>{value}</t></is></c>')
            else:
                shared.append(value)
                cells.append(f'<c r="{ref}" t="s"><v>{len(shared) - 1}</v></c>')
        sheet_rows.append(f'<row r="{r}">{"".join(cells)}</row>')
    ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
    rel_ns = 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("xl/workbook.xml", (
            f'<workbook {ns} {rel_ns}><sheets>'
            '<sheet name="가공식품" sheetId="1" r:id="rId1"/></sheets></workbook>'
        ))
        z.writestr("xl/_rels/workbook.xml.rels", (
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Target="worksheets/sheet1.xml" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"/>'
            '</Relationships>'
        ))
        z.writestr("xl/sharedStrings.xml", (
            f'<sst {ns}>' + "".join(f"<si><t>{s}</t></si>" for s in shared) + "</sst>"
        ))
        z.writestr("xl/worksheets/sheet1.xml", (
            f'<worksheet {ns}><sheetData>{"".join(sheet_rows)}</sheetData></worksheet>'
        ))


def test_import_reads_kfind_xlsx(tmp_path):
    """K-FIND 는 엑셀로만 준다. 받은 그대로 읽어야 변환 단계에서 틀릴 일이 없다."""
    from scripts.import_food_nutrients import _read

    path = tmp_path / "20260828_가공식품DB_2건.xlsx"
    _write_xlsx(path, [
        ["식품명", "대표식품명", "식품기원명", "식품중량", "에너지(kcal)", "당류(g)", "탄수화물(g)"],
        ["우유_흰", "우유", "가공식품", "200ml", 63, "", "4.7"],   # 당류 칸이 비어 있다
        ["우유_딸기", "우유", "가공식품", "200ml", 85.5, "10.2", ""],
    ], inline_first_row=True)
    rows = _read(path)
    assert [r["대표식품명"] for r in rows] == ["우유", "우유"]
    assert rows[0]["에너지(kcal)"] == "63" and rows[1]["에너지(kcal)"] == "85.5"
    # 빈 셀이 옆 칸을 당겨 오면 탄수화물이 당류 자리에 들어간다.
    assert rows[0]["당류(g)"] == "" and rows[0]["탄수화물(g)"] == "4.7"
    assert rows[1]["탄수화물(g)"] == ""
    assert "식품명" not in rows[0]            # 집계가 안 쓰는 열은 버린다(메모리)


def test_import_rejects_portal_truncated_file(tmp_path, monkeypatch):
    """공공데이터포털은 5만 건에서 오류 없이 자른다 — 잘린 원본으로 집계하면 안 된다."""
    import scripts.import_food_nutrients as importer

    path = tmp_path / "가공식품.csv"
    path.write_text("대표식품명,에너지(kcal)\n" + "우유,63\n" * 3, encoding="utf-8")
    monkeypatch.setattr(importer, "_TRUNCATED_AT", 3)
    with pytest.raises(SystemExit, match="잘린 파일"):
        importer._read(path)


def test_import_finds_kfind_file_by_its_download_name(tmp_path):
    from scripts.import_food_nutrients import _find_source

    assert _find_source(tmp_path, "가공식품") is None
    (tmp_path / "20260728_가공식품DB_310000건.xlsx").touch()
    (tmp_path / "20260828_가공식품DB_316734건.xlsx").touch()
    assert _find_source(tmp_path, "가공식품").name == "20260828_가공식품DB_316734건.xlsx"
    # 직접 이름 붙인 파일이 있으면 그것을 쓴다.
    (tmp_path / "가공식품.csv").touch()
    assert _find_source(tmp_path, "가공식품").name == "가공식품.csv"


def test_vision_parser_keeps_amount_g():
    """프롬프트가 amount_g 를 요구하는데 파서가 안 넘기면 보정이 폴백만 탄다."""
    import json

    from app.services.recognizer.litellm_vision import LiteLLMVisionRecognizer

    payload = json.dumps({
        "foods": [
            {"name": "김치찌개", "amount_g": 320.5, "calories": 100},
            {"name": "공기밥", "amount_g": 0, "calories": 300},      # 0 = 모름
            {"name": "국", "calories": 50},                          # 필드 없음
        ],
        "coach_comment": "",
    })
    analysis = LiteLLMVisionRecognizer._parse(
        LiteLLMVisionRecognizer.__new__(LiteLLMVisionRecognizer), payload, 0
    )
    assert [f.amount_g for f in analysis.foods] == [320.5, None, None]



# ---------- 참조표 캐시 (#424) ----------

def _count_queries(db, fn):
    """fn 실행 중 나간 SQL 문 개수."""
    from sqlalchemy import event

    n = 0

    def _seen(*_args, **_kw):
        nonlocal n
        n += 1

    bind = db.get_bind()
    event.listen(bind, "before_cursor_execute", _seen)
    try:
        fn()
    finally:
        event.remove(bind, "before_cursor_execute", _seen)
    return n


def test_nutrient_table_loads_once(db_session):
    """전건 로드가 요청마다 반복되면 안 된다 — 두 번째부터는 DB 를 안 친다."""
    from app.services.nutrition.table import invalidate, load_rows

    invalidate()
    assert _count_queries(db_session, lambda: load_rows(db_session)) == 1
    assert _count_queries(db_session, lambda: load_rows(db_session)) == 0
    # 캐시된 값도 실제 시드 내용이어야 한다(빈 튜플을 캐시해 놓고 통과하면 곤란).
    assert any(r.name_norm == "김치찌개" for r in load_rows(db_session))


def test_nutrient_table_cache_survives_detach(db_session):
    """캐시가 ORM 인스턴스면 세션이 닫힌 뒤 속성 접근에서 터진다."""
    from app.db.session import SessionLocal
    from app.services.nutrition.table import invalidate, load_rows

    invalidate()
    other = SessionLocal()
    try:
        rows = load_rows(other)
    finally:
        other.close()
    assert [r.name_norm for r in rows]          # detached 여도 읽힌다
    assert load_rows(db_session) is rows        # 다른 세션도 같은 캐시를 쓴다


def test_nutrient_table_cache_invalidated_on_commit(db_session):
    """시드가 갱신되면 캐시가 비워져야 한다 — 안 그러면 새 음식이 영영 안 잡힌다."""
    from app.models.models import FoodNutrient
    from app.services.nutrition.matcher import match_food, normalize
    from app.services.nutrition.table import load_rows

    load_rows(db_session)                       # 캐시 채우기
    assert match_food(db_session, "zzcacheinvalidate") is None

    row = FoodNutrient(
        name="zzcacheinvalidate", name_norm=normalize("zzcacheinvalidate"),
        calories=100, sodium_mg=10, sugar_g=1, serving_size_g=100,
    )
    db_session.add(row)
    db_session.commit()
    try:
        assert match_food(db_session, "zzcacheinvalidate") is not None
    finally:
        # 이 테스트는 삽입 전 상태(None)를 확인하므로 흔적을 남기면 재실행이 깨진다.
        db_session.delete(row)
        db_session.commit()


def test_nutrient_table_cache_invalidated_on_rollback(db_session):
    """되돌아간 트랜잭션의 행이 캐시에 남으면 안 된다."""
    from app.models.models import FoodNutrient
    from app.services.nutrition.matcher import match_food, normalize
    from app.services.nutrition.table import invalidate, load_rows

    invalidate()
    db_session.add(FoodNutrient(
        name="zzrollbackrow", name_norm=normalize("zzrollbackrow"),
        calories=100, sodium_mg=10, sugar_g=1, serving_size_g=100,
    ))
    db_session.flush()
    load_rows(db_session)                       # 미확정 행이 든 상태로 캐시 채우기
    db_session.rollback()

    assert match_food(db_session, "zzrollbackrow") is None
