"""큐레이션 영양 행에 탄·단·지를 채우고 PT 식단 세 항목을 더한다. (#2096)

`food_nutrients` 의 큐레이션 행은 칼로리·나트륨·당류만 있고 탄·단·지가 비어 있었다.
그래서 이 행에 붙은 음식은 인식기가 탄·단·지를 주지 않으면 0 이 됐다. 그리고
오트밀·그릭 요거트·닭가슴살은 표에 없어 엉뚱한 행(`밀`, `닭가슴살 샐러드`)에 붙었다.

시드(`app/data/food_nutrients_seed.py`)는 새 값을 갖고 있지만 **표가 비었을 때만**
넣으므로, 이미 떠 있는 DB 에는 닿지 않는다. 이 마이그레이션이 그 차이를 메운다.

**손댄 값은 덮어쓰지 않는다.** 탄·단·지가 셋 다 비어 있고 칼로리가 이 값을 계산한
큐레이션 칼로리 그대로일 때만 채운다 — 탄·단·지는 그 칼로리에 맞춰 환산한 것이라,
칼로리가 다른 행에 넣으면 둘이 어긋난다. 새 항목도 같은 이름이 없을 때만 넣는다.
되돌릴 때도 같은 조건으로 이 값 그대로일 때만 비우거나 지운다.

행이 없는 DB(새로 만든 DB)에서는 아무 일도 하지 않는다. 여기서 한 행이라도 넣으면
시드가 표가 찼다고 보고 공공 표준 2천여 행을 통째로 건너뛴다.

값은 100g 기준이고 시드를 `init_db._curated_per_100g` 로 환산한 것과 같아야 한다
(`tests/test_nutrition.py` 가 확인한다).

Revision ID: 0075_food_nutrient_macros
Revises: 0074_demo_trainer_names
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0075_food_nutrient_macros"
down_revision: str | Sequence[str] | None = "0074_demo_trainer_names"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

#: (name_norm, 칼로리, 탄수화물, 단백질, 지방) — 100g 기준.
MACROS: tuple[tuple[str, float, float, float, float], ...] = (
    ("공기밥", 147.62, 33.1, 2.81, 0.43),
    ("비빔밥", 120.0, 19.38, 3.8, 3.04),
    ("김밥", 240.0, 35.95, 8.65, 6.85),
    ("볶음밥", 155.0, 25.5, 5.72, 3.35),
    ("떡볶이", 183.33, 34.9, 5.4, 2.47),
    ("순대", 180.0, 22.7, 6.05, 7.2),
    ("김치찌개", 62.5, 3.95, 5.75, 2.62),
    ("된장찌개", 45.0, 4.65, 3.65, 1.3),
    ("순두부찌개", 55.0, 3.38, 4.92, 2.42),
    ("미역국", 36.67, 2.4, 3.93, 1.27),
    ("된장국", 30.0, 3.43, 2.27, 0.8),
    ("갈비탕", 61.43, 2.93, 4.41, 3.57),
    ("설렁탕", 57.14, 6.13, 3.97, 1.86),
    ("삼계탕", 90.0, 5.42, 7.93, 4.06),
    ("라면", 90.91, 13.29, 2.49, 3.09),
    ("짜장면", 107.69, 19.8, 3.69, 1.52),
    ("짬뽕", 94.29, 14.1, 5.24, 1.89),
    ("잔치국수", 87.27, 16.13, 3.16, 1.13),
    ("물냉면", 91.67, 16.4, 4.5, 0.9),
    ("삼겹살", 330.0, 0.0, 16.25, 29.45),
    ("제육볶음", 192.0, 10.6, 17.44, 8.88),
    ("불고기", 168.0, 5.6, 11.08, 11.24),
    ("양념갈비", 220.0, 6.84, 11.04, 16.48),
    ("후라이드치킨", 266.67, 14.57, 23.43, 12.73),
    ("양념치킨", 300.0, 28.33, 26.63, 8.9),
    ("돈까스", 292.0, 16.56, 14.36, 18.72),
    ("감자튀김", 315.38, 41.92, 3.46, 14.85),
    ("피자", 233.33, 24.08, 11.33, 10.17),
    ("햄버거", 220.0, 18.8, 11.04, 11.2),
    ("초밥", 240.0, 43.45, 10.15, 2.85),
    ("김치", 30.0, 5.0, 1.6, 0.4),
    ("계란후라이", 180.0, 3.2, 11.4, 13.6),
    ("계란찜", 75.0, 1.75, 6.8, 4.55),
    ("샐러드", 26.67, 5.0, 1.47, 0.13),
    ("아메리카노", 2.86, 0.0, 0.11, 0.03),
    ("콜라", 42.25, 10.99, 0.0, 0.0),
    ("우유", 65.0, 4.85, 3.3, 3.6),
    ("사과", 50.0, 11.65, 0.25, 0.3),
    ("바나나", 87.5, 20.58, 1.0, 0.17),
    ("식빵", 285.71, 42.14, 7.0, 9.86),
)

#: 새 항목 — 100g 기준. `serving_size_g` 는 인식기가 양을 못 줬을 때 쓰는 1회 섭취량이다.
NEW_ROWS: tuple[dict, ...] = (
    {
        "name": "오트밀",
        "category": "곡류",
        "serving_size_g": 240,
        "calories": 71.0,
        "sodium_mg": 4.0,
        "sugar_g": 0.27,
        "carbs_g": 12.0,
        "protein_g": 2.54,
        "fat_g": 1.52,
        "name_norm": "오트밀",
    },
    {
        "name": "그릭 요거트",
        "category": "유제품",
        "serving_size_g": 100,
        "calories": 97.0,
        "sodium_mg": 35.0,
        "sugar_g": 4.0,
        "carbs_g": 3.98,
        "protein_g": 9.0,
        "fat_g": 5.0,
        "name_norm": "그릭요거트",
    },
    {
        "name": "닭가슴살",
        "category": "육류",
        "serving_size_g": 100,
        "calories": 144.0,
        "sodium_mg": 328.0,
        "sugar_g": 0.0,
        "carbs_g": 0.0,
        "protein_g": 28.0,
        "fat_g": 3.57,
        "name_norm": "닭가슴살",
    },
)

_TOLERANCE = 0.005

_FILL = sa.text(
    "UPDATE food_nutrients SET carbs_g = :carbs, protein_g = :protein, fat_g = :fat "
    "WHERE name_norm = :name_norm AND ABS(calories - :kcal) < :tol "
    "AND carbs_g IS NULL AND protein_g IS NULL AND fat_g IS NULL"
)
_UNFILL = sa.text(
    "UPDATE food_nutrients SET carbs_g = NULL, protein_g = NULL, fat_g = NULL "
    "WHERE name_norm = :name_norm AND ABS(calories - :kcal) < :tol "
    "AND ABS(carbs_g - :carbs) < :tol AND ABS(protein_g - :protein) < :tol "
    "AND ABS(fat_g - :fat) < :tol"
)
# `source` 를 직접 적는다. 모델 기본값(`default="mfds"`)은 파이썬 쪽이라, `create_all`
# 로 만든 표에는 DB 기본값이 없어 빠뜨리면 NOT NULL 에 걸린다. 값은 시드가 넣는 것과
# 같은 `mfds` 다 — 새로 만든 DB 와 이 마이그레이션을 거친 DB 가 같은 행을 가져야 한다.
_INSERT = sa.text(
    "INSERT INTO food_nutrients "
    "(name, name_norm, category, serving_size_g, calories, sodium_mg, sugar_g, "
    "carbs_g, protein_g, fat_g, source) "
    "VALUES (:name, :name_norm, :category, :serving_size_g, :calories, :sodium_mg, "
    ":sugar_g, :carbs_g, :protein_g, :fat_g, 'mfds')"
)
_EXISTS = sa.text("SELECT 1 FROM food_nutrients WHERE name_norm = :name_norm")
_DELETE = sa.text(
    "DELETE FROM food_nutrients WHERE name_norm = :name_norm "
    "AND ABS(calories - :calories) < :tol AND ABS(protein_g - :protein_g) < :tol"
)


def _seeded(conn) -> bool:
    return conn.execute(sa.text("SELECT 1 FROM food_nutrients LIMIT 1")).first() is not None


def _macro_params(row: tuple[str, float, float, float, float]) -> dict:
    name_norm, kcal, carbs, protein, fat = row
    return {
        "name_norm": name_norm,
        "kcal": kcal,
        "carbs": carbs,
        "protein": protein,
        "fat": fat,
        "tol": _TOLERANCE,
    }


def fill(conn) -> None:
    """이미 시드된 표에 채운다. 빈 표에서는 아무 일도 하지 않는다."""
    if not _seeded(conn):
        return
    for row in MACROS:
        conn.execute(_FILL, _macro_params(row))
    for new in NEW_ROWS:
        # `INSERT … SELECT … WHERE NOT EXISTS` 한 문장으로 쓰면 psycopg 가 같은 자리표시자를
        # text 와 varchar 로 따로 추론해 거부한다 — 확인과 넣기를 나눈다.
        if conn.execute(_EXISTS, {"name_norm": new["name_norm"]}).first() is None:
            conn.execute(_INSERT, new)


def unfill(conn) -> None:
    """`fill` 이 넣은 값 그대로인 것만 되돌린다."""
    for new in NEW_ROWS:
        conn.execute(
            _DELETE,
            {
                "name_norm": new["name_norm"],
                "calories": new["calories"],
                "protein_g": new["protein_g"],
                "tol": _TOLERANCE,
            },
        )
    for row in MACROS:
        conn.execute(_UNFILL, _macro_params(row))


def upgrade() -> None:
    fill(op.get_bind())


def downgrade() -> None:
    unfill(op.get_bind())
