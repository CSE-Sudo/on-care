"""식단 `오늘` AI 맞춤 조언 — 규칙 한 줄 + 다음 식사 메뉴. (#2251)

보는 것:
1. 규칙 한 줄이 목표와 견준 수치를 말하고, 앞선 끼니가 비면 "적지 않은 끼니" 를 묻는다.
2. 다음 식사는 시각과 이미 적은 끼니로 정하고, 저녁 뒤 부족분이 남으면 간식이다.
3. 오늘 가장 급한 태그의 메뉴를 고르고, 그 이유가 충족되면 다른 메뉴로 바뀐다.
4. 최근 3일 안에 추천한 메뉴는 뒤로 미룬다.
5. 두 문장을 합쳐 45자 안팎이다.
"""
from __future__ import annotations

import json
import uuid
from datetime import datetime, time, timedelta

import pytest
from sqlalchemy import delete

from app.core import clock
from app.data import diet_menu_catalog as catalog
from app.services import diet_advice_copy as copy
from app.services import diet_coach_inputs as inputs
from app.services import diet_menu_plan
from app.services import diet_period_advice as svc
from app.services.diet_menu_plan import PlanMenu

TARGETS = inputs.DietTargets(calories=2000, protein_g=90, sodium_mg=2000, sugar_g=50)


def _totals(kcal=0, protein=0.0, sodium=0, sugar=0.0, slots=()):
    return svc.TodayTotals(
        kcal=kcal, protein_g=protein, sodium_mg=sodium, sugar_g=sugar,
        slots=frozenset(slots), has_entries=bool(slots),
    )


# ── 규칙 한 줄 ───────────────────────────────────────────────────────────


def test_analysis_empty_and_missing_meal():
    assert svc.analysis_today(_totals(), TARGETS, time(9)).key == "today_empty"
    # 11시가 지났는데 아침이 없다.
    t = _totals(kcal=600, protein=30, slots=("lunch",))
    assert svc.analysis_today(t, TARGETS, time(13)).key == "today_missing_meal"
    # 11시 전이면 아직 묻지 않는다.
    t = _totals(kcal=300, protein=20, slots=("snack",))
    assert svc.analysis_today(t, TARGETS, time(10, 30)).key != "today_missing_meal"


def test_analysis_priority_sodium_then_calorie_then_protein():
    at = time(10)
    slots = ("breakfast",)
    over = svc.analysis_today(_totals(2300, 20, 2100, slots=slots), TARGETS, at)
    assert (over.key, over.params) == ("today_sodium_over", {"sodium_mg": 2100})
    assert over.text == "나트륨 **2,100mg**, 권장량 초과예요."
    kcal = svc.analysis_today(_totals(2300, 20, 900, slots=slots), TARGETS, at)
    assert kcal.key == "today_calorie_over"
    protein = svc.analysis_today(_totals(500, 58, 900, slots=slots), TARGETS, at)
    assert (protein.key, protein.params) == ("today_protein_left", {"protein_g": 32})
    fine = svc.analysis_today(_totals(1500, 85, 900, slots=slots), TARGETS, at)
    assert fine.key == "today_balanced"


# ── 다음 끼니 ────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    ("slots", "at", "expected"),
    [
        ((), time(8), "breakfast"),
        ((), time(12), "lunch"),  # 아침 시각이 지났다
        (("breakfast",), time(9), "lunch"),
        (("lunch",), time(13), "dinner"),
        (("breakfast", "lunch"), time(20), "dinner"),
        (("dinner",), time(19), None),  # 저녁까지 적었다 → 간식 차례
        (("breakfast",), time(22), None),  # 밤이 늦었다
    ],
)
def test_next_slot(slots, at, expected):
    assert svc.next_slot(frozenset(slots), at) == expected


# ── 메뉴 고르기 ──────────────────────────────────────────────────────────


def _menu(name, tag, slot="dinner"):
    return PlanMenu(slot=slot, name=name, tag=tag, keyword=catalog.TAG_KEYWORDS["ko"][tag],
                    kcal=400, protein_g=20, sodium_mg=400)


DINNER = [
    _menu("닭가슴살 볶음", catalog.TAG_PROTEIN_HIGH),
    _menu("연두부찜", catalog.TAG_SODIUM_LOW),
    _menu("곤약 비빔면", catalog.TAG_CALORIE_LOW),
    _menu("잡곡 나물밥", catalog.TAG_FIBER_HIGH),
    _menu("연어 스테이크", catalog.TAG_PROTEIN_HIGH),
]


def test_pick_follows_the_most_urgent_need():
    t = _totals(kcal=900, protein=30, sodium=1500, slots=("breakfast", "lunch"))
    needs = svc.needs_today(t, TARGETS)
    assert needs[0] == catalog.TAG_SODIUM_LOW
    assert svc.pick_menu(DINNER, needs, set()).name == "연두부찜"


def test_pick_changes_once_the_reason_is_met():
    """단백질이 모자라면 고단백 — 단백질을 채우고 나면 다른 메뉴로 바뀐다."""
    short = _totals(kcal=900, protein=40, sodium=500, slots=("breakfast", "lunch"))
    assert svc.pick_menu(DINNER, svc.needs_today(short, TARGETS), set()).tag == catalog.TAG_PROTEIN_HIGH
    met = _totals(kcal=900, protein=85, sodium=500, slots=("breakfast", "lunch"))
    assert catalog.TAG_PROTEIN_HIGH not in svc.needs_today(met, TARGETS)
    picked = svc.pick_menu(
        DINNER, svc.needs_today(met, TARGETS), set(), svc.satisfied_today(met, TARGETS)
    )
    assert picked.tag != catalog.TAG_PROTEIN_HIGH


def test_pick_skips_recent_menus_but_keeps_the_reason():
    needs = [catalog.TAG_PROTEIN_HIGH]
    recent = {diet_menu_plan.norm_name("닭가슴살 볶음")}
    assert svc.pick_menu(DINNER, needs, recent).name == "연어 스테이크"
    # 이유가 맞는 메뉴가 모두 최근에 나왔으면, 다른 이유의 메뉴보다 그것을 다시 쓴다.
    recent |= {diet_menu_plan.norm_name("연어 스테이크")}
    assert svc.pick_menu(DINNER, needs, recent).tag == catalog.TAG_PROTEIN_HIGH


def test_snack_only_fills_what_can_be_added():
    salty = _totals(kcal=1900, protein=88, sodium=2600, slots=("breakfast", "lunch", "dinner"))
    assert svc.snack_needs(salty, TARGETS) == []
    short = _totals(kcal=1300, protein=60, sodium=900, slots=("breakfast", "lunch", "dinner"))
    assert svc.snack_needs(short, TARGETS) == [catalog.TAG_PROTEIN_HIGH, catalog.TAG_CALORIE_HIGH]


def test_two_sentences_stay_within_about_45_chars():
    """가장 긴 메뉴 이름과 네 자리 수를 넣어도 두 문장이 45자 안이다(한 문장 반, #1574).
    추천 이유 키워드는 문장에 싣지 않는다."""
    longest_name = "가" * diet_menu_plan.NAME_MAX["ko"]
    longest_kw = "나" * diet_menu_plan.KEYWORD_MAX["ko"]
    analyses = [
        copy.line("today_sodium_over", sodium_mg=9999),
        copy.line("today_calorie_over", kcal=9999),
        copy.line("today_protein_left", protein_g=120),
        copy.line("today_balanced", kcal=9999),
    ]
    actions = [
        copy.line("next_meal", slot="breakfast", menu=longest_name, keyword=longest_kw),
        copy.line("next_snack", menu=longest_name, keyword=longest_kw),
    ]
    for a in analyses:
        for b in actions:
            assert longest_kw not in b.text
            assert len(copy.message(a, b)) <= 45, copy.message(a, b)
    ask = copy.message(copy.line("today_missing_meal"), copy.line("today_log_first"))
    assert len(ask) <= 45


# ── DB ───────────────────────────────────────────────────────────────────


@pytest.fixture
def member(db_session):
    from app.core.security import hash_password
    from app.models.models import DietAdviceState, DietEntry, DietMenuPlan, HealthProfile, User

    user = User(
        id=f"user-{uuid.uuid4().hex[:12]}", email=f"today-{uuid.uuid4().hex[:8]}@example.com",
        name="오늘 조언", hashed_password=hash_password("pw!"), role="member",
    )
    db_session.add(user)
    db_session.add(HealthProfile(user_id=user.id, daily_protein_g=90))
    db_session.commit()
    yield user
    db_session.rollback()
    for model in (DietAdviceState, DietMenuPlan, DietEntry, HealthProfile):
        db_session.execute(delete(model).where(model.user_id == user.id))
    db_session.execute(delete(User).where(User.id == user.id))
    db_session.commit()


def _eat(db_session, user_id, day, meal, *, kcal=500, protein=20.0, sodium=500):
    from app.models.models import DietEntry

    db_session.add(DietEntry(
        id=f"diet-{uuid.uuid4().hex[:12]}", user_id=user_id, date=day.isoformat(),
        meal_type=meal, foods_json=json.dumps([{"name": "밥", "calories": kcal}], ensure_ascii=False),
        total_calories=kcal, protein_g=protein, sodium_mg=sodium, sugar_g=5,
    ))
    db_session.commit()


def _at(hour: int, minute: int = 0, day_offset: int = 0) -> datetime:
    base = datetime(2026, 9, 21, hour, minute, tzinfo=clock.SEOUL)
    return base + timedelta(days=day_offset)


def test_today_advice_without_records_still_recommends_a_meal(db_session, member):
    advice = svc.today_advice(db_session, member.id, now=_at(8), use_llm=False)
    assert advice.analysis.key == "today_empty"
    assert advice.action.key == "next_meal"
    assert advice.action.params["slot"] == "breakfast"
    assert advice.action_source == "plan"
    assert advice.days_logged == 0


def test_today_advice_follows_records_and_changes_menu_when_met(db_session, member):
    now = _at(13)
    _eat(db_session, member.id, now.date(), "breakfast", protein=15)
    _eat(db_session, member.id, now.date(), "lunch", protein=20)
    short = svc.today_advice(db_session, member.id, now=now, use_llm=False)
    assert short.analysis.key == "today_protein_left"
    assert short.action.params["slot"] == "dinner"
    plan = diet_menu_plan.get_plan(db_session, member.id, now=now, use_llm=False)
    picked = next(m for m in plan.for_slot("dinner") if m.name == short.action.params["menu"])
    assert picked.tag == catalog.TAG_PROTEIN_HIGH

    # 단백질을 채우면(간식) 이유가 충족되어 다른 태그의 메뉴로 바뀐다.
    _eat(db_session, member.id, now.date(), "snack", protein=60)
    met = svc.today_advice(db_session, member.id, now=now + timedelta(minutes=5), use_llm=False)
    menu = next(m for m in plan.for_slot("dinner") if m.name == met.action.params["menu"])
    assert menu.tag != catalog.TAG_PROTEIN_HIGH


def test_today_advice_after_dinner(db_session, member):
    now = _at(20)
    for meal in ("breakfast", "lunch", "dinner"):
        _eat(db_session, member.id, now.date(), meal, kcal=400, protein=15)
    snack = svc.today_advice(db_session, member.id, now=now, use_llm=False)
    assert snack.action.key == "next_snack"

    _eat(db_session, member.id, now.date(), "snack", kcal=600, protein=50)
    done = svc.today_advice(db_session, member.id, now=now, use_llm=False)
    assert done.action.key == "today_done"
    assert done.action_source == "rules"


def test_recent_picks_are_pushed_back_for_three_days(db_session, member):
    first = svc.today_advice(db_session, member.id, now=_at(8), use_llm=False)
    same_day = svc.today_advice(db_session, member.id, now=_at(9), use_llm=False)
    assert same_day.action.params["menu"] == first.action.params["menu"]

    next_day = svc.today_advice(db_session, member.id, now=_at(8, day_offset=1), use_llm=False)
    assert next_day.action.params["menu"] != first.action.params["menu"]

    # 나흘 뒤에는 다시 나올 수 있다(3일만 미룬다).
    later = svc.today_advice(db_session, member.id, now=_at(8, day_offset=4), use_llm=False)
    names = {m.name for m in diet_menu_plan.get_plan(
        db_session, member.id, now=_at(8, day_offset=4), use_llm=False).for_slot("breakfast")}
    assert later.action.params["menu"] in names


def test_endpoint_returns_two_sentences_and_keeps_message(client, db_session, monkeypatch):
    monkeypatch.setattr(diet_menu_plan, "_call_llm", lambda s, u: (_ for _ in ()).throw(RuntimeError("no key")))
    email = f"today-api-{uuid.uuid4().hex[:8]}@oncare.com"
    client.post("/v1/auth/register", json={"email": email, "password": "oncare123", "name": "조언"})
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "oncare123"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    body = client.get("/v1/diet/advice?period=today", headers=headers).json()
    assert body["analysis_key"] == "today_empty"
    assert body["action_key"] in ("next_meal", "next_snack", None)
    if body["action_key"]:
        assert "**" in body["action"]
        assert "**" not in body["message"]
        assert body["message"] == copy.plain(f"{body['analysis']} {body['action']}")

    en = client.get("/v1/diet/advice?period=today&lang=en", headers=headers).json()
    if en["action_key"]:
        assert en["action_params"]["menu"].isascii()
    assert client.get("/v1/diet/advice?period=today&lang=jp", headers=headers).status_code == 422

    # 전체는 아직 한 문장이다 — analysis 에도 같은 문장이 실린다.
    every = client.get("/v1/diet/advice?period=all", headers=headers).json()
    assert every["analysis"] == every["message"] and every["analysis_key"] is None


def test_missing_meal_asks_for_the_record_without_touching_the_plan(db_session, member, monkeypatch):
    """빠진 끼니를 묻는 동안은 메뉴를 고르지 않고, 리스트를 만들려고 AI 를 부르지도 않는다."""
    from sqlalchemy import func, select

    from app.models.models import DietMenuPlan

    calls = []
    monkeypatch.setattr(diet_menu_plan, "_call_llm", lambda s, u: calls.append(1) or "{}")
    now = _at(13)
    _eat(db_session, member.id, now.date(), "lunch")  # 11시가 지났는데 아침이 없다

    advice = svc.today_advice(db_session, member.id, now=now)
    assert advice.analysis.key == "today_missing_meal"
    assert advice.action.key == "today_log_first"
    assert advice.action_source == "rules"
    assert calls == []
    count = db_session.scalar(
        select(func.count()).select_from(DietMenuPlan).where(DietMenuPlan.user_id == member.id)
    )
    assert count == 0
