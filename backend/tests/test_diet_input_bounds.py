"""식단 입력의 숫자 상한·이름 길이·음식 수. (#3243)

열량·나트륨 칸은 `Integer` 라 상한 없이 받으면 칸을 넘는 값이 DB 오류(500)가 됐다.
이름 길이와 음식 수에도 상한이 없었다. 상한은 앱이 보낼 수 있는 값(공공 DB 가장 진한
값 × 인식 양 상한)을 모두 받는 선이다.
"""
from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.schemas.diet import RecognizedFood
from app.schemas.diet_api import (
    ENTRY_CALORIES_MAX,
    ENTRY_SODIUM_MG_MAX,
    FOOD_CALORIES_MAX,
    FOOD_SODIUM_MG_MAX,
    FOODS_MAX,
    DietEntryCreate,
    DietEntryUpdate,
    EditedFood,
    FoodNutritionRequest,
)
from app.services.recognizer.parse import AMOUNT_G_MAX, NAME_MAX

_INT32_MAX = 2**31 - 1


def test_entry_totals_fit_the_integer_column():
    assert ENTRY_CALORIES_MAX <= _INT32_MAX
    assert ENTRY_SODIUM_MG_MAX <= _INT32_MAX


def test_densest_db_food_at_the_largest_amount_is_accepted():
    """손대지 않은 음식을 그대로 되돌려 보내도 걸리지 않는다(기름·소금 × 5,000g)."""
    food = EditedFood(name="소금", calories=921 * 50, sodium_mg=9900 * 50)
    assert (food.calories, food.sodium_mg) == (46050, 495000)


@pytest.mark.parametrize("bad", [
    {"name": "가" * (NAME_MAX + 1)},
    {"name": "밥", "calories": FOOD_CALORIES_MAX + 1},
    {"name": "밥", "sodium_mg": FOOD_SODIUM_MG_MAX + 1},
    {"name": "밥", "calories": _INT32_MAX + 1},
])
def test_edited_food_rejects_values_over_the_bounds(bad):
    with pytest.raises(ValidationError):
        EditedFood(**bad)


def test_stored_records_still_read_without_bounds():
    """저장된 기록을 다시 읽는 `RecognizedFood` 에는 상한을 두지 않는다."""
    food = RecognizedFood(name="가" * 200, calories=FOOD_CALORIES_MAX + 1)
    assert food.calories == FOOD_CALORIES_MAX + 1


def test_food_count_is_bounded():
    foods = [{"name": "밥"}] * (FOODS_MAX + 1)
    with pytest.raises(ValidationError):
        DietEntryCreate(meal_type="lunch", foods=foods)
    with pytest.raises(ValidationError):
        DietEntryUpdate(foods=foods)
    assert len(DietEntryCreate(meal_type="lunch", foods=foods[:FOODS_MAX]).foods) == FOODS_MAX


@pytest.mark.parametrize("bad", [
    {"total_calories": ENTRY_CALORIES_MAX + 1},
    {"sodium_mg": ENTRY_SODIUM_MG_MAX + 1},
    {"total_calories": _INT32_MAX + 1},
])
def test_update_totals_are_bounded(bad):
    with pytest.raises(ValidationError):
        DietEntryUpdate(**bad)


def test_nutrition_lookup_bounds_name_and_amount():
    with pytest.raises(ValidationError):
        FoodNutritionRequest(name="가" * (NAME_MAX + 1))
    with pytest.raises(ValidationError):
        FoodNutritionRequest(name="밥", amount_g=AMOUNT_G_MAX + 1)
    assert FoodNutritionRequest(name="밥", amount_g=AMOUNT_G_MAX).amount_g == AMOUNT_G_MAX


def test_manual_entry_with_overflowing_calories_is_422_not_500(client):
    from app.core.security import create_access_token
    from app.db.init_db import DEMO_USER_ID

    headers = {"Authorization": f"Bearer {create_access_token(DEMO_USER_ID)}"}
    r = client.post(
        "/v1/diet/entries",
        json={"meal_type": "lunch", "foods": [{"name": "밥", "calories": _INT32_MAX + 1}]},
        headers=headers,
    )
    assert r.status_code == 422, r.text
