"""김민수 데모 데이터의 단일 원본을 읽는다.

사용자 앱의 `user-7d4e9a2c5f18` 와 트레이너 앱의 `seed-client-1` 은 같은 사람이다.
예전에는 두 앱과 백엔드가 각자 알고리즘으로 그의 과거를 만들어서, 같은 날짜를
나란히 놓으면 숫자가 어긋났다(#757). 이제 셋 다 이 픽스처만 읽는다 — 여기에
계산은 없고, 픽스처에 적힌 값을 날짜에 붙이는 일만 한다.

**이행률은 저장하지 않는다.** [FixtureDay.completion] 은 그날 루틴 항목 중
`done` 인 것의 비율이다. 퍼센트를 따로 적어 두면 화면의 "3개 중 2개 완료" 와
숫자가 갈라진다.

Dart 쪽 짝은 `shared/demo_fixture/lib/demo_fixture.dart` 다 — 날짜를 붙이는
규칙(주 격자 + 최근 사흘 덮어쓰기)을 양쪽이 똑같이 구현한다.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import date, timedelta
from functools import lru_cache
from pathlib import Path

#: 픽스처 파일. `shared/demo_fixture/assets/kim_minsu.json` 과 내용이 같다 —
#: 백엔드 이미지가 `backend/` 만 담기 때문에 여기에도 둔다(`tool/gen_demo_fixture.py`
#: 가 두 곳에 함께 쓴다).
FIXTURE_PATH = Path(__file__).with_name("demo_fixture_data.json")

_DAY_LABELS = ("월", "화", "수", "목", "금", "토", "일")


@dataclass(frozen=True)
class FixtureFood:
    name: str
    calories: int
    sodium_mg: int
    sugar_g: float
    carbs_g: float
    protein_g: float
    fat_g: float

    def as_row(self) -> dict:
        """화면·저장소가 읽는 키 이름 그대로. 세 곳이 같은 키를 쓴다."""
        return {
            "name": self.name,
            "calories": self.calories,
            "sodium_mg": self.sodium_mg,
            "sugar_g": self.sugar_g,
            "carbs_g": self.carbs_g,
            "protein_g": self.protein_g,
            "fat_g": self.fat_g,
        }


@dataclass(frozen=True)
class FixtureMeal:
    slug: str
    #: 시연 중 화면에서 지목하는 행만 id 를 못 박는다. 나머지는 None 이고 호출부가
    #: 날짜로 만든다.
    row_id: str | None
    meal_type: str
    time_label: str
    photo_asset: str
    ai_comment: str
    foods: tuple[FixtureFood, ...]

    @property
    def calories(self) -> int:
        return sum(f.calories for f in self.foods)

    @property
    def sodium_mg(self) -> int:
        return sum(f.sodium_mg for f in self.foods)

    @property
    def sugar_g(self) -> float:
        return round(sum(f.sugar_g for f in self.foods), 1)

    @property
    def carbs_g(self) -> float:
        return round(sum(f.carbs_g for f in self.foods), 1)

    @property
    def protein_g(self) -> float:
        return round(sum(f.protein_g for f in self.foods), 1)

    @property
    def fat_g(self) -> float:
        return round(sum(f.fat_g for f in self.foods), 1)

    def foods_json(self) -> str:
        return json.dumps([f.as_row() for f in self.foods], ensure_ascii=False)


@dataclass(frozen=True)
class FixtureExercise:
    name: str
    #: `cardio` | `strength` | `stretching` | `other` — 표준 어휘 (#996, #997).
    type: str
    minutes: int
    calories: int
    done: bool
    #: 근력 항목의 세트 수와 한 세트당 횟수. 다른 유형은 None 이다.
    #:
    #: 예전에는 이 값을 읽지 않고 버렸다 — Dart 쪽 짝은 읽는데 백엔드만 버려서,
    #: 실 API 로 붙이면 같은 회원의 같은 날 근력이 화면마다 다른 세트 수로
    #: 보였다(분에서 되짚은 수와 픽스처가 적어 둔 수가 달랐다). (#1265)
    sets: int | None = None
    reps: int | None = None
    #: 근력 항목의 중량(kg). 맨몸 운동은 0 이다 — 근력이면 언제나 값을 하나
    #: 든다(#1902). 예전에는 이 값이 이름 문자열에만 있어(`레그프레스 70kg`),
    #: 이름을 쓰는 화면과 필드를 읽는 화면이 같은 기록을 다르게 말했다.
    weight: float | None = None

    @property
    def label(self) -> str:
        """트레이너 화면이 쓰는 표기. 이행률과 이 목록이 같은 자리에서 나온다(#754)."""
        return f"{self.name} {'✓' if self.done else '✗'}"


@dataclass(frozen=True)
class FixtureRoutine:
    """회원에게 배정된 개인운동 한 줄. Dart 쪽 `FixtureRoutine` 과 같은 내용이다.

    출처(`source`)가 픽스처에 있는 것이 중요하다 — 회원 앱은 이 값으로 `트레이너
    추천` 과 `AI 추천 · 트레이너 확인` 을 갈라 적는다. 실서버 시드가 따로 든 표를
    읽던 동안은 이 구분이 실연동에서 사라졌다(#1199).
    """

    #: 실서버 시드가 쓰는 것과 같은 id. 두 앱이 같은 루틴을 같은 줄로 가리킨다.
    id: str
    name: str
    minutes: int
    #: 운동 유형 — 유산소|근력|스트레칭|기타 (모델과 같은 한국어 어휘).
    type: str
    reason: str
    #: `ai` | `trainer`.
    source: str
    #: 근력 배정의 세트 수·한 세트당 횟수·중량(kg). 다른 유형은 None 이다(#1276)
    #: — 유형마다 재는 단위가 다르다. 맨몸 운동은 중량만 비어 있다.
    sets: int | None = None
    reps: int | None = None
    weight: float | None = None


@dataclass(frozen=True)
class FixtureDay:
    day: date
    meals: tuple[FixtureMeal, ...]
    exercises: tuple[FixtureExercise, ...]
    routine_label: str
    is_pt: bool
    client_feedback: str
    trainer_note: str
    day_message: str

    @property
    def iso(self) -> str:
        return self.day.isoformat()

    @property
    def week_start(self) -> str:
        """그 주 월요일. 운동은 주 단위로 조회된다."""
        return (self.day - timedelta(days=self.day.weekday())).isoformat()

    @property
    def day_label(self) -> str:
        return _DAY_LABELS[self.day.weekday()]

    @property
    def has_record(self) -> bool:
        return bool(self.meals or self.exercises)

    @property
    def calories(self) -> int:
        return sum(m.calories for m in self.meals)

    @property
    def sodium_mg(self) -> int:
        return sum(m.sodium_mg for m in self.meals)

    @property
    def sugar_g(self) -> float:
        return round(sum(m.sugar_g for m in self.meals), 1)

    @property
    def completion(self) -> int:
        """이행률(%) — 저장된 값이 아니라 `done` 개수에서 나온다. 휴식일은 0."""
        if not self.exercises:
            return 0
        done = sum(1 for e in self.exercises if e.done)
        return round(done * 100 / len(self.exercises))

    @property
    def done_exercises(self) -> tuple[FixtureExercise, ...]:
        """실제로 한 운동만. 주간 활동 합계가 이걸 쌓는다."""
        return tuple(e for e in self.exercises if e.done)


class DemoFixture:
    """픽스처 파일 한 벌."""

    def __init__(self, payload: dict) -> None:
        member = payload["member"]
        self.member_name: str = member["name"]
        #: 사용자 앱 데모 계정 id.
        self.user_app_seed_id: str = member["userAppSeedId"]
        #: 트레이너 앱에서 같은 사람을 가리키는 고객 id.
        self.trainer_client_id: str = member["trainerClientId"]
        #: 픽스처가 덮는 주 수(이번 주 포함).
        self.history_weeks: int = payload["historyWeeks"]
        self._foods = {
            key: FixtureFood(
                name=value["name"],
                calories=value["calories"],
                sodium_mg=value["sodiumMg"],
                sugar_g=value["sugarG"],
                carbs_g=value["carbsG"],
                protein_g=value["proteinG"],
                fat_g=value["fatG"],
            )
            for key, value in payload["foods"].items()
        }
        self._meals: dict[str, dict] = payload["meals"]
        #: 배정된 개인운동. 실서버 시드도 이 목록을 읽는다(#1199).
        self.routines: tuple[FixtureRoutine, ...] = tuple(
            FixtureRoutine(
                id=item["id"],
                name=item["name"],
                minutes=item["minutes"],
                type=item["type"],
                reason=item["reason"],
                source=item["source"],
                sets=item.get("sets"),
                reps=item.get("reps"),
                weight=item.get("weight"),
            )
            for item in payload.get("routines", ())
        )
        self._recent: list[dict] = payload["recent"]
        self._weeks: list[dict] = payload["weeks"]

    def days_for(self, today: date) -> list[FixtureDay]:
        """[today] 기준으로 날짜가 붙은 하루들을 오래된 → 오늘 순으로 돌려준다.

        주 격자가 달력 주를 채우고, 최근 사흘(오늘·어제·그제)이 그 위를 덮는다.
        아직 오지 않은 요일은 넣지 않는다 — 넣으면 주간 추이 그래프가 빈 날을
        막대로 그리고 주 평균도 실제보다 높아진다(#752).
        """
        this_monday = today - timedelta(days=today.weekday())
        by_date: dict[date, FixtureDay] = {}

        for week in self._weeks:
            week_monday = this_monday - timedelta(days=7 * week["weeksAgo"])
            for entry in week["days"]:
                day = week_monday + timedelta(days=entry["weekday"])
                if day > today:
                    continue
                by_date[day] = self._day_from(entry, day)

        for entry in self._recent:
            day = today - timedelta(days=entry["offset"])
            by_date[day] = self._day_from(entry, day)

        return [by_date[key] for key in sorted(by_date)]

    def _day_from(self, entry: dict, day: date) -> FixtureDay:
        return FixtureDay(
            day=day,
            meals=tuple(self._meal_from(meal) for meal in entry["meals"]),
            exercises=tuple(
                FixtureExercise(
                    name=item["name"],
                    type=item["type"],
                    minutes=item["minutes"],
                    calories=item["calories"],
                    done=item["done"],
                    sets=item.get("sets"),
                    reps=item.get("reps"),
                )
                for item in entry["exercises"]
            ),
            routine_label=entry.get("label", ""),
            is_pt=entry.get("pt", False),
            client_feedback=entry.get("clientFeedback", ""),
            trainer_note=entry.get("trainerNote", ""),
            day_message=entry.get("dayMessage", ""),
        )

    def _meal_from(self, entry: dict) -> FixtureMeal:
        slug = entry["meal"]
        template = self._meals[slug]
        return FixtureMeal(
            slug=slug,
            row_id=entry.get("id"),
            meal_type=template["mealType"],
            time_label=entry.get("timeLabel", template["timeLabel"]),
            photo_asset=template["photoAsset"],
            ai_comment=entry.get("aiComment", template["aiComment"]),
            foods=tuple(self._foods[key] for key in template["foods"]),
        )


@lru_cache(maxsize=1)
def load_fixture() -> DemoFixture:
    """픽스처를 읽는다. 파일은 바뀌지 않으므로 한 번만 읽는다."""
    return DemoFixture(json.loads(FIXTURE_PATH.read_text(encoding="utf-8")))
