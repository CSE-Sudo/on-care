"""김민수 데모 픽스처 — 파일 자체와 백엔드 리더를 본다.

시드가 DB 에 옮긴 결과는 `test_member_seed.py` 가 본다.
"""
from __future__ import annotations

import json
from datetime import date
from pathlib import Path

from app.db.demo_fixture import FIXTURE_PATH, load_fixture
from app.services import exercise_types
from app.services.exercise_service import estimate_calories

#: Flutter 두 앱이 읽는 원본. 백엔드 이미지는 `backend/` 만 담아서 같은 파일을
#: 한 벌 더 갖고 있다 — 두 파일이 어긋나면 두 앱과 백엔드의 숫자가 갈라진다.
SHARED_PATH = (
    Path(__file__).resolve().parents[2]
    / "shared/demo_fixture/assets/kim_minsu.json"
)


def test_backend_copy_matches_the_shared_original():
    # 손으로 맞추지 말 것 — `python3 tool/gen_demo_fixture.py` 가 두 곳에 함께 쓴다.
    assert FIXTURE_PATH.read_bytes() == SHARED_PATH.read_bytes()


def test_every_demo_food_knows_how_much_was_eaten():
    """데모 식단의 모든 음식에 내용량이 있다 (#2090).

    내용량은 나머지 영양이 무엇을 재고 나온 값인가다(#1876). 비어 있으면 화면은
    아무것도 적지 않으므로(0g 은 안 먹었다로 읽힌다) 데모에서 양이 보이지 않는다.
    """
    fixture = load_fixture()
    for day in fixture.days_for(date(2026, 8, 16)):
        for meal in day.meals:
            for food in meal.foods:
                assert food.amount_g > 0, food.name
            # 시드가 DB 에 옮기는 글자에도 실린다.
            stored = json.loads(meal.foods_json())
            assert all(row["amount_g"] > 0 for row in stored), meal.slug


def test_curated_days_keep_the_numbers_the_demo_says_out_loud():
    days = load_fixture().days_for(date(2026, 8, 16))
    today, yesterday = days[-1], days[-2]

    assert (today.calories, today.sodium_mg, today.sugar_g) == (1054, 4657, 16.7)
    assert (yesterday.calories, yesterday.sodium_mg, yesterday.sugar_g) == (
        3231,
        1338,
        64.2,
    )


def test_no_day_lies_in_the_future():
    # 주중에 열어도 이번 주 남은 요일이 채워지면 주 평균이 실제보다 높아진다(#752).
    for today in (date(2026, 8, 10), date(2026, 8, 13), date(2026, 8, 16)):
        days = load_fixture().days_for(today)
        assert days[-1].day == today
        assert not [d for d in days if d.day > today]


def test_completion_comes_from_the_routine_items():
    for day in load_fixture().days_for(date(2026, 8, 16)):
        if not day.exercises:
            assert day.completion == 0
            continue
        done = sum(1 for e in day.exercises if e.done)
        assert day.completion == round(done * 100 / len(day.exercises))


def test_the_fixture_covers_its_history_without_gaps():
    """몇 주를 들고 있는지는 픽스처가 정한다.

    여기 숫자를 적으면 기간을 늘릴 때마다 두 곳을 고쳐야 한다.
    """
    fixture = load_fixture()
    days = fixture.days_for(date(2026, 8, 16))  # 일요일 → 기간이 꽉 찬다
    expected = fixture.history_weeks * 7
    assert len(days) == expected
    assert len({d.iso for d in days}) == expected


def test_exercise_calories_match_the_app_estimate():
    """픽스처의 칼로리는 앱·서버가 쓰는 추정표와 같은 값이어야 한다. (#997)

    예전에는 픽스처만 분당 7.5·5 로 낮았다. 그래서 데모의 30분 유산소는
    225kcal 인데, 같은 운동을 회원이 직접 기록하면 270kcal 이 나왔다 — 같은
    사람의 같은 운동이 어느 경로로 들어왔는지에 따라 다른 숫자가 됐다.
    """
    for day in load_fixture().days_for(date(2026, 8, 16)):
        for exercise in day.exercises:
            assert exercise.calories == estimate_calories(
                exercise.type, exercise.minutes, "moderate"
            ), f"{day.iso} {exercise.name}"


def test_exercise_types_use_the_standard_vocabulary():
    """유형은 표준 네 가지로만 적는다 — 옛 이름이 픽스처에 다시 들어오지 않게. (#996)"""
    for day in load_fixture().days_for(date(2026, 8, 16)):
        for exercise in day.exercises:
            assert exercise.type in exercise_types.CANONICAL_TYPES, exercise.type


# ── 데모가 과거에도 서 있는가 (#1265) ──────────────────────────────────────
#
# 데모는 오늘 하루만 보는 것이 아니다. 지난주·전체로 넘겼을 때 PT 를 받은 날,
# 그때 무엇을 몇 세트 했는지, 회원이 뭐라고 했고 트레이너가 뭘 적어 뒀는지가
# 없으면 "운동 기능이 충분히 구현된 제품" 으로 읽히지 않는다.
#
# 시연 날짜를 미리 알 수 없으므로 **어느 요일에 열어도** 성립해야 한다. 아래
# 검사는 월~일 일곱 요일과 연·월 경계, 윤년 하루를 함께 본다.
_ANY_DAY = (
    date(2026, 8, 10),   # 월
    date(2026, 8, 11),   # 화
    date(2026, 8, 12),   # 수
    date(2026, 8, 13),   # 목
    date(2026, 8, 14),   # 금
    date(2026, 8, 15),   # 토
    date(2026, 8, 16),   # 일
    date(2026, 12, 31),  # 연말
    date(2027, 1, 1),    # 연초
    date(2028, 2, 29),   # 윤년
)


def test_the_past_has_pt_days_spread_across_the_history():
    """과거에 PT 사례가 흩어져 있다 — 오늘 하나뿐이면 지난 기간이 비어 보인다."""
    for today in _ANY_DAY:
        days = load_fixture().days_for(today)
        past_pt = [d for d in days if d.is_pt and d.day < today]
        assert len(past_pt) >= 5, f"{today}: 과거 PT 가 {len(past_pt)}일뿐"
        for day in past_pt:
            assert day.client_feedback, f"{day.iso}: 고객 피드백이 없다"
            assert day.trainer_note, f"{day.iso}: 트레이너 메모가 없다"
            assert any(
                e.type == exercise_types.STRENGTH and e.sets
                for e in day.exercises
            ), f"{day.iso}: 세트를 적은 근력이 없다"


def test_every_exercise_type_shows_up_in_more_than_one_week():
    """네 유형이 모두, 여러 주에 걸쳐 보인다.

    `other` 가 하나도 없으면 유형별 분해 화면의 `기타` 칸이 늘 0 이라, 그 칸이
    실제로 동작하는지 시연에서 볼 수가 없다.
    """
    days = load_fixture().days_for(date(2026, 8, 16))
    weeks_by_type: dict[str, set[str]] = {}
    for day in days:
        for exercise in day.exercises:
            kind = exercise_types.normalize(exercise.type)
            weeks_by_type.setdefault(kind, set()).add(day.week_start)
    for kind in exercise_types.CANONICAL_TYPES:
        weeks = weeks_by_type.get(kind, set())
        assert len(weeks) >= 2, f"{kind}: {len(weeks)}주에만 보인다"


def test_today_is_a_pt_day_of_strength_only():
    """월요일에 열어도 이번 주 화면이 비지 않는다 — 오늘 하루가 PT 를 담고 있다.

    다만 종목은 **근력뿐**이다. 사용자앱의 `오늘 완료한 PT` 카드가 근력 종목을
    줄로 세우므로, 오늘에 다른 유형을 얹으면 카드에는 없는데 `운동 현황 · 오늘`
    에만 있는 운동 시간이 생긴다. 네 유형은 기간 전체가 책임진다
    (`test_every_exercise_type_shows_up_in_more_than_one_week`).
    """
    for today in _ANY_DAY:
        day = load_fixture().days_for(today)[-1]
        assert day.day == today
        kinds = {exercise_types.normalize(e.type) for e in day.exercises}
        assert kinds == {exercise_types.STRENGTH}, f"{today}: {kinds}"
        assert day.is_pt, f"{today}: 오늘이 PT 날이 아니다"
        assert day.client_feedback and day.trainer_note
        assert any(
            e.type == exercise_types.STRENGTH and e.sets for e in day.exercises
        )


def test_strength_always_says_how_many_sets():
    """근력은 세트를 값으로 들고 다닌다 — 분에서 되짚으면 화면마다 수가 갈린다."""
    for day in load_fixture().days_for(date(2026, 8, 16)):
        for exercise in day.exercises:
            if exercise_types.normalize(exercise.type) != exercise_types.STRENGTH:
                assert exercise.sets is None, f"{day.iso}: {exercise.name}"
                continue
            assert exercise.sets, f"{day.iso}: {exercise.name} 에 세트가 없다"
