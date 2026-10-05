"""칼로리를 모르는 음식이 섞인 날의 식단 조회.

사진 인식이 칼로리를 읽지 못하면 음식 한 줄의 `calories` 가 `None` 으로 저장되고,
옛 문자열 항목(#724)은 칼로리 키 자체가 없다. 회원 앱은 음식마다 정수 칼로리를
받는다고 보고 읽어서, 이런 줄이 하나라도 섞이면 그날 식단 전체가 오류 화면이
됐다. 응답의 모든 음식 항목은 정수 칼로리를 싣는다(모르면 0).
"""
from __future__ import annotations

import json

import pytest

from app.schemas.diet import RecognizedFood
from app.services.diet_service import load_foods, store_foods


# ── 저장 표현 → 조회 표현 ────────────────────────────────────────────────


def test_recognized_none_calories_round_trip_to_zero():
    stored = store_foods([
        RecognizedFood(name="김치찌개", calories=None),
        RecognizedFood(name="현미밥", calories=300),
    ])
    # 저장은 지금처럼 모름(null)을 그대로 남긴다 — 정규화는 읽는 쪽 일이다.
    assert stored[0]["calories"] is None

    foods = load_foods(json.dumps(stored, ensure_ascii=False))
    assert [f["calories"] for f in foods] == [0, 300]
    assert foods[0]["name"] == "김치찌개"


def test_missing_calories_key_becomes_zero():
    foods = load_foods(json.dumps([{"name": "나물"}], ensure_ascii=False))
    assert foods == [{"name": "나물", "calories": 0}]


def test_legacy_string_items_get_integer_calories():
    foods = load_foods(json.dumps(["김치찌개", 42, None, "  "], ensure_ascii=False))
    assert foods == [{"name": "김치찌개", "calories": 0}]


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        (250, 250),
        (249.6, 250),
        ("180", 180),
        (" 75.4 ", 75),
        ("많이", 0),
        (-30, 0),
        (True, 0),
        ([], 0),
        ({"kcal": 10}, 0),
    ],
)
def test_calories_are_always_non_negative_int(raw, expected):
    foods = load_foods(json.dumps([{"name": "x", "calories": raw}]))
    assert foods[0]["calories"] == expected
    assert type(foods[0]["calories"]) is int


def test_non_finite_calories_become_zero():
    # json.dumps 는 기본으로 NaN/Infinity 를 쓴다 — 저장된 행에 섞여 있어도 견딘다.
    foods = load_foods(
        '[{"name": "a", "calories": NaN}, {"name": "b", "calories": Infinity}]'
    )
    assert [f["calories"] for f in foods] == [0, 0]


def test_other_fields_are_untouched():
    stored = store_foods([
        RecognizedFood(name="닭가슴살", calories=None, protein_g=23.0, amount_g=100.0),
    ])
    food = load_foods(json.dumps(stored))[0]
    assert food["protein_g"] == 23.0
    assert food["amount_g"] == 100.0
    assert food["sodium_mg"] is None


# ── API ─────────────────────────────────────────────────────────────────


def _member_headers() -> dict[str, str]:
    from app.core.security import create_access_token
    from app.db.init_db import DEMO_USER_ID
    from app.db.session import SessionLocal
    from app.models.models import User

    with SessionLocal() as db:
        version = db.get(User, DEMO_USER_ID).token_version
    token = create_access_token(DEMO_USER_ID, token_version=version)
    return {"Authorization": f"Bearer {token}"}


def test_day_with_unknown_calorie_foods_returns_integer_calories(client, db_session):
    from app.db.init_db import DEMO_USER_ID
    from app.models.models import DietEntry

    day = "2099-03-03"
    db_session.add_all([
        DietEntry(
            id="diet-kcal-none",
            user_id=DEMO_USER_ID,
            date=day,
            meal_type="lunch",
            foods_json=json.dumps(
                [
                    {"name": "김치찌개", "calories": None, "source": "estimate"},
                    {"name": "현미밥", "calories": 300, "source": "db"},
                    {"name": "나물"},
                ],
                ensure_ascii=False,
            ),
            total_calories=300,
        ),
        DietEntry(
            id="diet-kcal-legacy",
            user_id=DEMO_USER_ID,
            date=day,
            meal_type="dinner",
            foods_json=json.dumps(["된장국", 7, None], ensure_ascii=False),
            total_calories=150,
        ),
    ])
    db_session.commit()
    try:
        r = client.get(f"/v1/diet/days/{day}", headers=_member_headers())
        assert r.status_code == 200, r.text
        entries = {e["id"]: e for e in r.json()["entries"]}

        lunch = entries["diet-kcal-none"]["foods"]
        assert [f["calories"] for f in lunch] == [0, 300, 0]
        dinner = entries["diet-kcal-legacy"]["foods"]
        assert dinner == [{"name": "된장국", "calories": 0}]
        for entry in entries.values():
            assert all(isinstance(f["calories"], int) for f in entry["foods"])
            assert isinstance(entry["total_calories"], int)
    finally:
        db_session.query(DietEntry).filter(
            DietEntry.id.in_(["diet-kcal-none", "diet-kcal-legacy"])
        ).delete(synchronize_session=False)
        db_session.commit()
