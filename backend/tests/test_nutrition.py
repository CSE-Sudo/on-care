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
    # 끝말 규칙으로는 `스테이크`(소고기)에 붙는 단백질 요리 (#2100)
    rows = _rows("스테이크", "닭가슴살", "연어", "스파게티", "후라이드치킨")
    assert match_in_rows(rows, "닭가슴살 스테이크").name_norm == "닭가슴살"
    assert match_in_rows(rows, "연어 스테이크").name_norm == "연어"
    assert match_in_rows(rows, "크림 파스타").name_norm == "스파게티"
    assert match_in_rows(rows, "순살 치킨").name_norm == "후라이드치킨"
    rows = _rows("공기밥", "스크램블드에그", "농후발효유", "그래놀라 토핑")
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
    """`init_db._seed_food_nutrients` 가 넣는 것과 같은 행 — DB 없이."""
    from app.db.init_db import _food_nutrient_seed_rows
    from app.services.nutrition.table import NutrientRow

    return tuple(
        NutrientRow(id=i, **{k: row[k] for k in (
            "name", "name_norm", "category", "serving_size_g", "calories", "sodium_mg",
            "sugar_g", "carbs_g", "protein_g", "fat_g",
        )})
        for i, row in enumerate(_food_nutrient_seed_rows())
    )


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

    own = [item for item in FOOD_NUTRIENTS if "from_public" not in item]
    for row in _curated_per_100g(own):
        macros = (row.get("carbs_g"), row.get("protein_g"), row.get("fat_g"))
        assert None not in macros, row["name"]
        # 아메리카노(열량이 탄·단·지에서 오지 않는다)·술(열량 대부분이 알코올)
        if row["calories"] < 20 or row["category"] == "주류":
            continue
        atwater = macros[0] * 4 + macros[1] * 4 + macros[2] * 9
        assert atwater == pytest.approx(row["calories"], rel=0.12), row["name"]


def test_blank_macros_come_only_from_label_values():
    """#2102: 탄·단·지가 빈 공공 행은 원본에서 채울 수 없는 것뿐이어야 한다.

    업체 표시값(`수집`)은 탄·단·지를 적지 않은 일이 많고, 원재료성식품은 지방을 재지
    않은 행이 있다. 같은 음식의 레시피 계산값에는 탄·단·지가 있지만 체계적으로 낮아
    (열량 ×0.76) 섞으면 한 행의 값 한 벌이 깨진다 — 비워 두면 인식기 값이 채운다.
    """
    from app.db.init_db import _public_food_rows

    blank = [r for r in _public_food_rows() if None in (r["carbs_g"], r["protein_g"], r["fat_g"])]
    assert blank
    for r in blank:
        assert r["method"] == "수집" or r["source_dataset"] == "원재료성식품", r["name"]


def test_aliases_point_at_seeded_rows():
    """대상이 없는 별칭은 조용히 무시되므로, 오타가 나도 아무도 모른다."""
    from app.services.nutrition.matcher import ALIASES

    names = {r.name_norm for r in _seed_rows()}
    for alias, target in ALIASES.items():
        assert normalize(target) in names, target
        # 표 이름과 같으면 별칭이 아니라 그 행이 붙는다.
        assert normalize(alias) not in names, alias


# ---------- 시드 동기화 (#2100) ----------

def _id_range(db):
    from sqlalchemy import text

    return tuple(db.execute(text("SELECT min(id), max(id) FROM food_nutrients")).one())


def test_seed_resyncs_a_running_db_when_seed_data_changes(db_session):
    """시드를 고쳐도 떠 있는 DB 에 닿지 않던 문제 — 지문이 다르면 통째로 다시 맞춘다."""
    from sqlalchemy import text

    from app.db.init_db import _fingerprint, _food_nutrient_seed_rows, _seed_food_nutrients
    from app.models.models import ReferenceDataVersion
    from app.services.nutrition.matcher import match_food

    # 옛 시드로 채워진 DB: 값이 다르고 지문도 옛것이다.
    db_session.execute(text("UPDATE food_nutrients SET calories = 1 WHERE name_norm = '김치찌개'"))
    db_session.execute(text(
        "UPDATE reference_data_versions SET fingerprint = 'stale' WHERE name = 'food_nutrients'"
    ))
    db_session.commit()

    _seed_food_nutrients()

    db_session.expire_all()
    seed = next(r for r in _food_nutrient_seed_rows() if r["name_norm"] == "김치찌개")
    assert match_food(db_session, "김치찌개").calories == pytest.approx(seed["calories"])
    stored = db_session.get(ReferenceDataVersion, "food_nutrients")
    assert stored.fingerprint == _fingerprint(_food_nutrient_seed_rows())


def test_seed_leaves_the_table_alone_when_seed_data_is_unchanged(db_session):
    """기동할 때마다 표를 갈아엎으면 안 된다 — 통째로 바꾸면 행 id 가 새로 매겨진다."""
    from app.db.init_db import _seed_food_nutrients

    _seed_food_nutrients()
    before = _id_range(db_session)
    _seed_food_nutrients()
    db_session.expire_all()
    assert _id_range(db_session) == before


def test_seed_resyncs_a_db_that_has_no_fingerprint_yet(db_session):
    """0076 직후 첫 기동: 지문이 없으니 한 번 다시 맞춘다 — 떠 있는 DB 가 새 값을 받는 경로."""
    from sqlalchemy import text

    from app.db.init_db import _seed_food_nutrients
    from app.models.models import ReferenceDataVersion

    db_session.execute(text("DELETE FROM reference_data_versions WHERE name = 'food_nutrients'"))
    db_session.commit()
    before = _id_range(db_session)

    _seed_food_nutrients()

    db_session.expire_all()
    assert _id_range(db_session) != before
    assert db_session.get(ReferenceDataVersion, "food_nutrients") is not None


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
    # 두 행이 똑같이 전형적이면 열량이 낮은 행 — 두 값의 평균(253)을 만들지 않는다(#2100).
    assert out[0]["calories"] == 252.0


def test_import_serving_hint_ignores_sale_units():
    """1회 섭취량 힌트에는 판매 단위(라지 피자 한 판, 여럿이 나눠 먹는 외식 메뉴)를 쓰지 않는다.

    가정식 분석이 가정 1인분을 조리해 잰 무게라 1인분에 가장 가깝다(#2102).
    """
    from scripts.import_food_nutrients import aggregate

    rows = [
        _raw("피자_라지", "피자", "외식(프랜차이즈 등 업체 제공 영양정", "1640g", "252", "416", "3.7"),
        _raw("피자_외식", "피자", "외식(분석함량)", "964g", "250", "410", "3.6"),
        _raw("피자_가정", "피자", "가정식(분석 함량)", "200g", "254", "420", "3.5"),
        _raw("피자_급식", "피자", "산업체급식(재료량 기반 산출 함량)", "300g", "254", "420", "3.5"),
    ]
    [out] = aggregate(rows, "음식")
    assert out["serving_size_g"] == 200.0
    assert out["serving_basis"] == "가정식 분석"


def test_import_serving_falls_back_through_portion_rows():
    """가정식 1인분이 없으면 성인 급식, 그다음 외식 레시피 1인분. 학교 급식은 쓰지 않는다.

    학교 급식은 학년별 배식 기준이라 성인 1인분이 아니다(중고등 `쌀밥` 450g, 초등 250g).
    """
    from scripts.import_food_nutrients import aggregate

    school = [
        _raw("국_초등", "무국", "초등학교급식(재료량 기반 산출 함량)", "180ml", "20", "300", "1"),
        _raw("국_중고", "무국", "중고등학교급식(재료량 기반 산출 함량)", "450ml", "20", "300", "1"),
    ]
    out = aggregate([*school, _raw("국_외식", "무국", "외식(재료량 기반 산출함량)", "600ml", "20", "300", "1")], "음식")
    assert (out[0]["serving_size_g"], out[0]["serving_basis"]) == (600.0, "외식 레시피")
    out = aggregate([*school, _raw("국_산업", "무국", "산업체급식(재료량 기반 산출 함량)", "320ml", "20", "300", "1"),
                     _raw("국_외식", "무국", "외식(재료량 기반 산출함량)", "600ml", "20", "300", "1")], "음식")
    assert (out[0]["serving_size_g"], out[0]["serving_basis"]) == (320.0, "산업체 급식")


def test_import_serving_ignores_the_nutrient_basis_written_as_weight():
    """2022년 외식 분석처럼 `식품중량` 에 영양 기준량(100g)을 그대로 적은 칸은 1인분이 아니다."""
    from scripts.import_food_nutrients import aggregate

    [out] = aggregate([_raw("달걀찜_채소", "달걀찜", "가정식(분석 함량)", "100g", "89", "329", "0")], "음식")
    assert out["serving_size_g"] is None


@pytest.mark.parametrize(("rep", "category", "grams"), [
    ("배추김치", "김치류", 40.0),        # [표3] 배추김치
    ("열무물김치", "김치류", 80.0),      # [표3] 물김치
    ("쌀밥", "밥류", 210.0),             # [표3] 즉석조리식품 밥
    ("돼지고기 덮밥", "밥류", None),     # 덮밥은 밥 210g 이 아니다
    ("마늘장아찌", "장아찌·절임류", 15.0),
    ("해물탕", "국 및 탕류", 250.0),
    ("송편", "빵 및 과자류", 100.0),     # [표3] 떡류
    ("식빵", "빵 및 과자류", 70.0),      # [표3] 빵류
    ("돈가스", "튀김류", None),          # [표3] 에 없는 요리는 비운다
])
def test_import_serving_falls_back_to_the_reference_amount_for_dishes(rep, category, grams):
    """1인분 행이 없는 음식은 그 분류의 [표3] 1회 섭취참고량을 쓴다 — 없으면 비운다."""
    from scripts.import_food_nutrients import aggregate

    row = _raw(rep, rep, "외식(분석함량)", "100g", "100", "300", "1", category)
    [out] = aggregate([row], "음식")
    assert out["serving_size_g"] == grams
    assert out["serving_basis"] == ("표시기준 1회 섭취참고량" if grams else "")


def _packaged(name, rep, reference, kind="", kcal="100", basis="100g", weight="1000g", cat="음료류"):
    row = _raw(name, rep, "가공식품", weight, kcal, "10", "1", cat)
    row.update({"탄수화물(g)": "10", "단백질(g)": "1", "지방(g)": "1", "식품소분류명": kind,
                "영양성분함량기준량": basis, "1회 섭취참고량": reference, "데이터생성방법명": "수집"})
    return row


@pytest.mark.parametrize(("row", "grams"), [
    # 포장 무게(1L)가 아니라 1회 섭취참고량. ml 은 공공 집계와 같은 밀도로 g 이 된다.
    (_packaged("멸균우유", "우유(멸균)", "200ml", "우유", "61", "100ml", "1000ml", "유가공품류"), 206.0),
    (_packaged("양조간장", "간장", "5ml", "양조간장", "54", "100ml", "900ml", "장류"), 5.6),
    (_packaged("즉석국", "국/탕류", "250ml(g)", "즉석조리식품", "37"), 250.0),  # 괄호는 "g 이나 ml"
    (_packaged("건면", "파스타 건면", "생·숙면 200g, 건면 100g, 당면 30g, 유탕면(봉지)120g, 유탕면(용기)80g",
               "건면", "350", cat="면류"), 100.0),
    # 봉지·용기를 원본으로 가를 수 없다.
    (_packaged("유탕면", "기타 라면", "생·숙면 200g, 건면 100g, 당면 30g, 유탕면(봉지)120g, 유탕면(용기)80g",
               "유탕면", "450", cat="면류"), None),
    (_packaged("도시락", "도시락", "1식", "즉석섭취식품", "157"), None),   # 무게가 아니다
    # 타서 마신 양(200ml)이다 — 분말의 100g 당 값(380kcal)에 곱하면 조리 상태가 어긋난다.
    (_packaged("율무차분말", "고형차", "200ml", "고형차", "380"), None),
])
def test_import_serving_of_packaged_food_is_the_reference_amount(row, grams):
    """가공식품 1회 섭취량은 원본의 `1회 섭취참고량`(식약처 「식품등의 표시기준」 [표3])이다."""
    from scripts.import_food_nutrients import aggregate

    [out] = aggregate([row], "가공식품")
    assert out["serving_size_g"] == (None if grams is None else pytest.approx(grams))


def test_import_serving_of_packaged_food_follows_the_row_that_gives_the_values():
    """한 대표식품에 식품유형이 섞이면 값을 준 행의 1회 섭취참고량을 쓴다.

    `기타 라면` 은 건조 유탕면(450kcal/100g)이 대부분인데, 숙면 몇 개의 200g 을 붙이면
    유탕면 값에 200g 을 곱해 900kcal 이 된다.
    """
    from scripts.import_food_nutrients import aggregate

    noodle = "생·숙면 200g, 건면 100g, 당면 30g, 유탕면(봉지)120g, 유탕면(용기)80g"
    fried = [_packaged(f"유탕면_{i}", "기타 라면", noodle, "유탕면", str(445 + i), cat="면류") for i in range(4)]
    boiled = [_packaged("숙면", "기타 라면", noodle, "숙면", "160", cat="면류")]
    [out] = aggregate(fried + boiled, "가공식품")
    assert out["calories"] > 400
    assert out["serving_size_g"] is None


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


def _raw_full(name, kcal, na, sugar, carbs, protein, fat):
    row = _raw(name, "감자튀김", "외식(프랜차이즈 등 업체 제공 영양정", "100g", kcal, na, sugar, "튀김류")
    row.update({"탄수화물(g)": carbs, "단백질(g)": protein, "지방(g)": fat})
    return row


def test_import_takes_all_values_from_one_source_row():
    """#2100: 영양소마다 따로 중앙값을 내면 열량과 탄·단·지가 다른 제품에서 온다.

    아래에서 영양소별 중앙값은 열량 300·탄수화물 40·지방 15 로, 어느 제품에도 없는
    조합이다. 한 행의 값 한 벌을 써야 4·4·9 로 다시 셈한 열량이 표시 열량과 맞는다.
    """
    from scripts.import_food_nutrients import aggregate

    rows = [
        _raw_full("가", "250", "200", "0.3", "40", "3", "8"),
        _raw_full("나", "300", "210", "0.3", "38", "4", "15"),
        _raw_full("다", "320", "220", "0.4", "42", "3.5", "15.5"),
    ]
    [out] = aggregate(rows, "음식")
    assert (out["calories"], out["carbs_g"], out["protein_g"], out["fat_g"]) == (300.0, 38.0, 4.0, 15.0)


def test_import_prefers_the_most_typical_row_over_all_nutrients():
    """열량만 가운데인 제품은 나트륨이 치우쳐 있을 수 있다 — 모든 영양소를 함께 본다."""
    from scripts.import_food_nutrients import aggregate

    rows = [
        _raw_full("열량만 가운데", "300", "900", "1", "40", "4", "13"),   # 나트륨이 혼자 튄다
        _raw_full("전형", "305", "210", "1", "40", "4", "13.5"),
        _raw_full("비슷", "295", "205", "1", "39", "4", "13"),
        _raw_full("비슷2", "310", "215", "1", "41", "4", "14"),
    ]
    [out] = aggregate(rows, "음식")
    assert out["sodium_mg"] < 300


def test_import_prefers_rows_with_macros_unless_they_are_extreme():
    """탄·단·지가 빈 행을 고르면 그 음식은 인식기 값에 기댄다 — 찬 행이 있으면 그 행."""
    from scripts.import_food_nutrients import aggregate

    rows = [
        _raw_full("탄단지 없음", "300", "210", "1", "", "", ""),
        _raw_full("탄단지 없음2", "301", "211", "1", "", "", ""),
        _raw_full("탄단지 있음", "320", "230", "1.2", "40", "4", "15"),
    ]
    [out] = aggregate(rows, "음식")
    assert out["carbs_g"] == 40.0


def test_import_prefers_analysed_over_recipe_calculated_rows():
    """레시피 계산값은 분석값보다 체계적으로 낮다(음식 313종 비교: 열량 ×0.76, 나트륨 ×0.71).

    계산값이 더 많아도 분석값·업체 표시값이 있으면 그것을 쓴다 — `라면` 은 분석값 나트륨
    270~491mg 인데 계산값은 58~128mg 이다.
    """
    from scripts.import_food_nutrients import aggregate

    def row(kcal, na, method):
        r = _raw_full("라면", kcal, na, "0.1", "13", "2.5", "3")
        r["데이터생성방법명"] = method
        return r

    rows = [row("79", "58", "산출"), row("79", "60", "산출"), row("95", "91", "산출"),
            row("99", "352", "분석"), row("92", "333", "분석")]
    [out] = aggregate(rows, "음식")
    assert out["sodium_mg"] > 300


def test_import_treats_label_values_like_analysed_ones():
    """업체 표시값은 분석값과 거의 같다(×0.96). 소수의 분석 제품이 대표를 정하면 안 된다.

    가공식품 `카레` 는 분석 행이 고형 카레 하나라, 분석을 앞세우면 425kcal·나트륨
    4,059mg 이 된다. 데우기만 하는 카레 제품 표시값 여럿이 대표가 되어야 한다.
    """
    from scripts.import_food_nutrients import aggregate

    def row(name, kcal, na, method):
        r = _raw_full(name, kcal, na, "3", "12", "2.5", "3")
        r["데이터생성방법명"] = method
        return r

    rows = [row("고형카레", "425", "4059", "분석"),
            row("카레_가", "95", "620", "수집"), row("카레_나", "100", "640", "수집"),
            row("카레_다", "105", "610", "수집")]
    [out] = aggregate(rows, "가공식품")
    assert out["calories"] < 200


def test_import_keeps_distinct_products_with_equal_labels():
    """라벨 값이 우연히 같은 서로 다른 제품은 합치지 않는다 — 이름이 다르면 다른 표본이다."""
    from scripts.import_food_nutrients import aggregate

    drinks = [_raw_full(f"차음료_{i}", "0", "5", "0", "0", "0", "0") for i in range(5)]
    leaves = [_raw_full("찻잎_가", "330", "7", "1", "60", "20", "2"),
              _raw_full("찻잎_나", "320", "9", "1", "58", "22", "2")]
    [out] = aggregate(drinks + leaves, "가공식품")
    assert out["calories"] == 0.0


def test_import_counts_duplicated_canteen_rows_once():
    """급식 데이터는 같은 계산값을 급식 종류마다 복제한다 — 복제 수가 '전형' 을 정하면 안 된다."""
    from scripts.import_food_nutrients import aggregate

    dup = [_raw_full("호떡", "147", "2", "5", "20.14", "2.7", "5.91") for _ in range(4)]
    rows = [*dup,
            _raw_full("호떡_꿀", "300", "230", "15", "55", "5.4", "7"),
            _raw_full("호떡_흑당", "314", "211", "16", "57", "5.4", "7.1"),
            _raw_full("호떡_견과", "320", "240", "14", "56", "6", "7.5")]
    [out] = aggregate(rows, "음식")
    assert out["calories"] >= 300


def _lone(name, kcal, na, method):
    r = _raw_full(name, kcal, na, "1", "5", "1.5", "1")
    r.update({"대표식품명": "오이무침", "식품대분류명": "생채·무침류", "데이터생성방법명": method})
    return r


def _calculated(n, kcal="30", na="230"):
    return [_lone(f"오이무침_계산{i}", kcal, str(int(na) + i), "산출") for i in range(n)]


def test_import_distrusts_a_lone_analysis_far_from_the_recipes():
    """#2102: 분석값이 한 건뿐이면 레시피 계산값과 맞춰 본다.

    `오이무침` 은 부추를 넣은 분석 한 건이 나트륨 1,070mg 이고, 계산값 6건은 보정해도
    333mg 안팎이다. 2배 넘게 어긋나면 그 한 건 대신 계산값에서 고른다.
    """
    from scripts.import_food_nutrients import aggregate

    [out] = aggregate([_lone("오이무침_부추", "31", "1070", "분석"), *_calculated(6)], "음식")
    assert out["sodium_mg"] < 300
    assert out["method"] == "산출"


def test_import_keeps_a_lone_analysis_close_to_the_recipes():
    """계산값은 분석값보다 체계적으로 낮다(열량 ×0.76, 나트륨 ×0.71) — 그만큼은 어긋난 게 아니다."""
    from scripts.import_food_nutrients import aggregate

    [out] = aggregate([_lone("오이무침", "40", "420", "분석"), *_calculated(6)], "음식")
    assert (out["sodium_mg"], out["method"]) == (420.0, "분석")


def test_import_keeps_a_lone_analysis_when_recipes_are_few():
    """계산값이 몇 건 안 되면 그 중앙값도 흔들려 비교의 기준이 못 된다."""
    from scripts.import_food_nutrients import aggregate

    [out] = aggregate([_lone("오이무침_부추", "31", "1070", "분석"), *_calculated(4)], "음식")
    assert out["sodium_mg"] == 1070.0


def test_import_ignores_tiny_absolute_gaps_for_a_lone_analysis():
    """값이 아주 작으면 비율만 커진다(`잡곡밥` 나트륨 3mg ↔ 계산값 1mg) — 잡음으로 본다."""
    from scripts.import_food_nutrients import aggregate

    [out] = aggregate([_lone("잡곡밥", "146", "3", "분석"), *_calculated(6, kcal="120", na="1")], "음식")
    assert (out["sodium_mg"], out["method"]) == (3.0, "분석")


def _raw_ml(name, rep, kcal, na, method="수집", cat="식용유지류", weight="500ml"):
    r = _raw_full(name, kcal, na, "0", "0", "0", "91")
    r.update({"대표식품명": rep, "식품대분류명": cat, "영양성분함량기준량": "100ml",
              "데이터생성방법명": method, "식품중량": weight, "식품기원명": "가공식품"})
    return r


def test_import_converts_100ml_values_to_100g():
    """앱은 그램을 곱한다 — 100ml 값을 100g 값으로 쓰면 식용유 열량이 8% 작다(밀도 0.92)."""
    from scripts.import_food_nutrients import aggregate

    row = _raw_ml("올리브유_가", "올리브유", "828", "0")
    row["1회 섭취참고량"] = "5ml"
    [oil] = aggregate([row], "가공식품")
    assert oil["calories"] == pytest.approx(900.0, abs=0.1)        # 828 ÷ 0.92
    # 1회 섭취량도 같은 밀도로 g 이 된다 — 포장(500ml)이 아니라 1회 섭취참고량이다(#2102).
    assert oil["serving_size_g"] == pytest.approx(4.6)             # 5ml × 0.92

    [ice] = aggregate([_raw_ml("바닐라콘", "아이스크림", "112", "40", cat="빙과류")], "가공식품")
    assert ice["calories"] == pytest.approx(200.0, abs=0.1)        # 공기가 들어 밀도 0.56


def test_import_leaves_ml_rows_without_a_density_source():
    """FAO 밀도 자료에 없는 것(식초)과 급식 계산값의 형식상 100ml 는 그대로 둔다."""
    from scripts.import_food_nutrients import aggregate

    [vinegar] = aggregate([_raw_ml("현미식초", "식초", "20", "5", cat="조미식품")], "가공식품")
    assert vinegar["calories"] == 20.0
    [canteen] = aggregate([_raw_ml("우유", "우유", "65", "40", method="산출", cat="유제품류")], "음식")
    assert canteen["calories"] == 65.0


def test_import_uses_the_plain_raw_row_for_raw_ingredients():
    """원재료성식품은 `{이름}_생것` 이 그 이름이 뜻하는 것이다 — 싹·말린 잎이 뽑히면 안 된다."""
    from scripts.import_food_nutrients import aggregate

    def raw(name, kcal, protein):
        r = _raw_full(name, kcal, "16", "1", "5", protein, "0.3")
        r.update({"대표식품명": "브로콜리", "식품기원명": "식물성", "데이터생성방법명": "분석"})
        return r

    rows = [raw("브로콜리_싹_생것", "31", "3.81"), raw("브로콜리_잎_말린것", "258", "20"),
            raw("브로콜리_분말화한것", "284", "25"), raw("브로콜리_생것", "32", "2.9"),
            raw("브로콜리_데친것", "28", "2.8")]
    for r in rows:
        r["식품대분류명"] = "채소류"
    [out] = aggregate(rows, "원재료성식품")
    assert (out["calories"], out["protein_g"]) == (32.0, 2.9)


def test_import_splits_distinct_foods_sharing_one_raw_group():
    """`호박` 묶음에는 단호박·애호박이 함께 있다 — 하나로 고르면 나머지가 틀린다."""
    from scripts.import_food_nutrients import aggregate

    def raw(name, kcal):
        r = _raw_full(name, kcal, "1", "3", "10", "1", "0.2")
        r.update({"대표식품명": "호박", "식품기원명": "식물성", "데이터생성방법명": "분석",
                  "식품대분류명": "채소류"})
        return r

    rows = [raw("호박_단호박_생것", "57"), raw("호박_단호박_찐것", "66"),
            raw("호박_애호박_생것", "22"), raw("호박_애호박_말린것", "284"),
            raw("호박_잎_생것", "45")]
    out = {r["name"]: r["calories"] for r in aggregate(rows, "원재료성식품")}
    assert out["단호박"] == 57.0 and out["애호박"] == 22.0


def test_import_keeps_dried_default_for_nuts_and_legumes():
    """땅콩·팥은 말린 것이 기본형이다 — 생것 규칙을 쓰면 볶은 땅콩(567kcal)이 풋땅콩이 된다."""
    from scripts.import_food_nutrients import aggregate

    def raw(name, kcal):
        r = _raw_full(name, kcal, "5", "4", "16", "25", "49")
        r.update({"대표식품명": "땅콩", "식품기원명": "식물성", "데이터생성방법명": "분석",
                  "식품대분류명": "견과 및 종실류"})
        return r

    rows = [raw("땅콩_생것", "318"), raw("땅콩_말린것", "567"), raw("땅콩_볶은것", "585"),
            raw("땅콩_버터", "590")]
    [out] = aggregate(rows, "원재료성식품")
    assert out["calories"] > 500


def test_import_renames_product_classes_that_wear_everyday_names():
    """가공식품 `파스타` 는 건면이다 — 일상어 `파스타` 를 비워 두고 별칭이 요리로 보낸다."""
    from scripts.import_food_nutrients import aggregate

    row = _raw_full("탈리아텔레", "350", "0", "3", "71", "13", "1.5")
    row["대표식품명"] = "파스타"
    [out] = aggregate([row], "가공식품")
    assert out["name"] == "파스타 건면"


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
    """큐레이션 값은 같은 이름의 공공 집계보다 우선한다 — 공공 쪽이 레시피 계산값뿐일 때다."""
    from app.services.nutrition.matcher import match_food

    jjajang = match_food(db_session, "짜장면")
    assert jjajang is not None
    # 큐레이션 2,400mg/650g → 100g 당 369.2. 공공 짜장면은 계산값 295mg 이다.
    assert round(jjajang.sodium_mg, 1) == 369.2
    assert match_food(db_session, "가공우유") is not None   # 가공식품 데이터셋


def test_public_servings_name_their_basis():
    """#2102: 공공 행의 1회 섭취량은 근거가 있을 때만 있다(`serving_basis`)."""
    from app.db.init_db import _public_food_rows

    rows = _public_food_rows()
    assert rows
    for r in rows:
        assert bool(r["serving_size_g"]) == bool(r["serving_basis"]), r["name"]


def test_curated_from_public_takes_the_public_values():
    """근거 있는 공공 값이 있으면 큐레이션은 이름과 1회 섭취량만 정한다(#2100)."""
    from app.data.food_nutrients_seed import FOOD_NUTRIENTS
    from app.db.init_db import _public_food_rows

    public = {normalize(r["name"]): r for r in _public_food_rows()}
    rows = {r.name: r for r in _seed_rows()}
    linked = [item for item in FOOD_NUTRIENTS if "from_public" in item]
    assert linked
    for item in linked:
        source = public[normalize(item["from_public"])]
        row = rows[item["name"]]
        assert (row.calories, row.sodium_mg, row.protein_g) == (
            source["calories"], source["sodium_mg"], source["protein_g"]
        ), item["name"]
        assert row.serving_size_g == item["serving_size_g"], item["name"]


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
        ["식품명", "대표식품명", "식품기원명", "식품중량", "에너지(kcal)", "당류(g)", "탄수화물(g)", "업체명"],
        ["우유_흰", "우유", "가공식품", "200ml", 63, "", "4.7", "가"],   # 당류 칸이 비어 있다
        ["우유_딸기", "우유", "가공식품", "200ml", 85.5, "10.2", "", "나"],
    ], inline_first_row=True)
    rows = _read(path)
    assert [r["대표식품명"] for r in rows] == ["우유", "우유"]
    assert rows[0]["에너지(kcal)"] == "63" and rows[1]["에너지(kcal)"] == "85.5"
    # 빈 셀이 옆 칸을 당겨 오면 탄수화물이 당류 자리에 들어간다.
    assert rows[0]["당류(g)"] == "" and rows[0]["탄수화물(g)"] == "4.7"
    assert rows[1]["탄수화물(g)"] == ""
    assert "업체명" not in rows[0]            # 집계가 안 쓰는 열은 버린다(메모리)


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
