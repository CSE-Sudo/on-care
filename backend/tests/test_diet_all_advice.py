"""식단 `전체` AI 맞춤 조언 — 최근 4주 식습관, 주 한 번. (#2254)

보는 것:
1. 최근 28일만 읽고, 기록이 7일 미만이면 AI 없이 안내한다.
2. 반복 패턴·편중·추세·자주 먹은 메뉴·반복 음식 중 하나를 말하고, 지난주에 말한
   종류는 한 번 건너뛴다.
3. 한 주 동안 같은 조언을 두고, AI 가 실패했으면 1시간 뒤 다시 만든다.
"""
from __future__ import annotations

import json
import uuid
from datetime import date, datetime, timedelta

import pytest
from sqlalchemy import delete

from app.core import clock
from app.services import diet_advice_copy as copy
from app.services import diet_ai_sentence as ai
from app.services import diet_all_advice as svc
from app.services import diet_coach_inputs as inputs
from app.services.diet_week_advice import DayRecord

TARGETS = inputs.DietTargets(calories=2000, protein_g=90, sodium_mg=2000, sugar_g=50)
TODAY = date(2026, 9, 24)  # 목요일


def _rec(day, meals, protein=90):
    r = DayRecord(day=day, protein_g=protein)
    r.meals = meals
    r.slots = {m[0] for m in meals}
    return r


def _meal(slot, name, sodium=500, kcal=500, protein=25):
    return (slot, [name], kcal, protein, sodium, 5)


# ── 규칙 ────────────────────────────────────────────────────────────────


def test_slot_sodium_finds_the_salty_slot():
    records = {}
    for i in range(10):
        day = TODAY - timedelta(days=i + 1)
        dinner = _meal("dinner", "짬뽕", sodium=1800 if i < 5 else 400)
        records[day] = _rec(day, [_meal("lunch", "비빔밥", sodium=600), dinner])
    f = svc.slot_sodium(records, TARGETS)
    assert (f.analysis.key, f.analysis.params) == ("all_slot_sodium", {"slot": "dinner", "days": 5})
    assert f.analysis.text == "최근 4주 저녁 나트륨이 **5번** 높았어요."
    assert "짬뽕" in f.records[0]


def test_slot_sodium_needs_to_be_frequent():
    day = TODAY - timedelta(days=1)
    records = {day: _rec(day, [_meal("dinner", "짬뽕", sodium=1800)])}
    assert svc.slot_sodium(records, TARGETS) is None


class _E:
    def __init__(self, carbs, protein, fat, name="밥"):
        self.carbs_g, self.protein_g, self.fat_g = carbs, protein, fat
        self.foods_json = json.dumps([{"name": name}], ensure_ascii=False)


def test_macro_bias():
    heavy = svc.macro([_E(300, 40, 20)])
    assert heavy.analysis.key == "all_carb_heavy" and heavy.analysis.params["pct"] >= 65
    light = svc.macro([_E(150, 20, 60)])
    assert light.analysis.key == "all_protein_light"
    assert svc.macro([_E(200, 100, 50)]) is None


def test_protein_trend_compares_two_fortnights():
    records = {}
    for i in range(1, 28):
        day = TODAY - timedelta(days=i)
        recent = i <= 13
        records[day] = _rec(day, [_meal("lunch", "밥")], protein=95 if (recent and i <= 8) else 50)
    f = svc.trend(records, TARGETS, TODAY)
    assert (f.analysis.key, f.analysis.params) == ("all_protein_trend_up", {"before": 0, "after": 8})
    assert f.analysis.text == "단백질 목표 달성일이 **0일→8일**로 늘었어요."


def test_frequent_menu_and_repeated_foods():
    records = {}
    for i in range(14):
        day = TODAY - timedelta(days=i + 1)
        lunch = _meal("lunch", "김치찌개" if i < 9 else "비빔밥")
        records[day] = _rec(day, [lunch, _meal("dinner", "닭가슴살")])
    f = svc.frequent(records)
    assert f.analysis.key == "all_frequent_menu"
    assert f.analysis.params == {"slot": "dinner", "food": "닭가슴살", "count": 14}
    r = svc.repeated(records)
    assert r.analysis.params == {"food1": "닭가슴살", "food2": "김치찌개"}


def test_choose_skips_last_weeks_kind_once():
    a = svc.Finding("slot_sodium", copy.line("all_slot_sodium", slot="dinner", days=5), "", ())
    b = svc.Finding("frequent", copy.line("all_frequent_menu", slot="lunch", food="밥", count=5), "", ())
    assert svc.choose([a, b], None) is a
    assert svc.choose([a, b], "slot_sodium") is b
    assert svc.choose([a], "slot_sodium") is a  # 말할 것이 그것뿐이면 다시 말한다
    assert svc.choose([], None) is None


def test_every_all_line_fits_with_its_fallback_tip():
    worst = [
        copy.line("all_slot_sodium", slot="breakfast", days=28),
        copy.line("all_carb_heavy", pct=100),
        copy.line("all_protein_light", pct=10),
        copy.line("all_protein_trend_up", before=14, after=14),
        copy.line("all_protein_trend_down", before=14, after=14),
        copy.line("all_frequent_menu", slot="breakfast", food="가" * svc.FREQUENT_NAME_MAX, count=28),
        copy.line("all_repeated_foods", food1="가" * 6, food2="나" * 6),
    ]
    for analysis in worst:
        tip = copy.line(svc._TIPS[analysis.key])
        assert len(copy.message(analysis, tip)) <= 45, analysis.key
        assert len(copy.plain(analysis.text)) + 1 + ai.MIN_SENTENCE["ko"] <= 45, analysis.key
    assert len(copy.message(copy.line("all_good", days=28), copy.line("tip_keep"))) <= 45
    assert len(copy.message(copy.line("all_few_records", days=6), copy.line("all_few_hint"))) <= 45


# ── DB ───────────────────────────────────────────────────────────────────


@pytest.fixture
def member(db_session):
    from app.core.security import hash_password
    from app.models.models import DietAdviceState, DietEntry, HealthProfile, User

    user = User(
        id=f"user-{uuid.uuid4().hex[:12]}", email=f"all-{uuid.uuid4().hex[:8]}@example.com",
        name="전체 조언", hashed_password=hash_password("pw!"), role="member",
    )
    db_session.add(user)
    db_session.add(HealthProfile(user_id=user.id, daily_protein_g=90))
    db_session.commit()
    yield user
    db_session.rollback()
    for model in (DietAdviceState, DietEntry, HealthProfile):
        db_session.execute(delete(model).where(model.user_id == user.id))
    db_session.execute(delete(User).where(User.id == user.id))
    db_session.commit()


def _eat(db_session, user_id, day, meal, name, *, sodium=500):
    from app.models.models import DietEntry

    db_session.add(DietEntry(
        id=f"diet-{uuid.uuid4().hex[:12]}", user_id=user_id, date=day.isoformat(),
        meal_type=meal, foods_json=json.dumps([{"name": name, "calories": 500}], ensure_ascii=False),
        total_calories=500, carbs_g=60, protein_g=30, fat_g=15, sodium_mg=sodium, sugar_g=5,
    ))


def _salty_dinners(db_session, user_id, days=10):
    for i in range(days):
        day = TODAY - timedelta(days=i + 1)
        _eat(db_session, user_id, day, "lunch", "김치찌개")  # 다음 주에 말할 거리
        _eat(db_session, user_id, day, "dinner", f"찌개{i}", sodium=1800)
    db_session.commit()


def _at(days=0, hours=0):
    return datetime(2026, 9, 24, 19, tzinfo=clock.SEOUL) + timedelta(days=days, hours=hours)


class _FakeAI:
    def __init__(self, fail=False):
        self.fail, self.calls, self.prompts = fail, 0, []

    def __call__(self, system, user):
        self.calls += 1
        self.prompts.append((system, user))
        if self.fail:
            raise RuntimeError("키 없음")
        return '{"sentence": "생선을 주 2회 넣어요."}'


def test_few_records_do_not_call_ai(db_session, member, monkeypatch):
    fake = _FakeAI()
    monkeypatch.setattr(ai, "_call_llm", fake)
    _salty_dinners(db_session, member.id, days=6)
    advice = svc.all_advice(db_session, member.id, now=_at())
    assert (advice.analysis.key, advice.analysis.params) == ("all_few_records", {"days": 6})
    assert advice.action.key == "all_few_hint"
    assert fake.calls == 0


def test_all_advice_reads_four_weeks_and_is_kept_for_the_week(db_session, member, monkeypatch):
    fake = _FakeAI()
    monkeypatch.setattr(ai, "_call_llm", fake)
    _salty_dinners(db_session, member.id)
    # 28일보다 오래된 기록은 읽지 않는다.
    _eat(db_session, member.id, TODAY - timedelta(days=40), "dinner", "옛 찌개", sodium=5000)
    db_session.commit()

    advice = svc.all_advice(db_session, member.id, now=_at())
    assert advice.analysis.key == "all_slot_sodium"
    assert advice.from_date == (TODAY - timedelta(days=27)).isoformat()
    assert (advice.action.text, advice.action_source) == ("생선을 주 2회 넣어요.", "llm")
    system, user = fake.prompts[0]
    assert "다음 4주" in system and "옛 찌개" not in user and "찌개0" in user

    # 같은 주(일요일까지)는 다시 만들지 않는다.
    svc.all_advice(db_session, member.id, now=_at(days=3))
    assert fake.calls == 1

    # 다음 주에는 지난주에 말한 종류(끼니별 나트륨)를 한 번 건너뛴다.
    nxt = svc.all_advice(db_session, member.id, now=_at(days=4))
    assert fake.calls == 2
    assert nxt.analysis.key != "all_slot_sodium"


def test_all_advice_falls_back_and_retries(db_session, member, monkeypatch):
    fake = _FakeAI(fail=True)
    monkeypatch.setattr(ai, "_call_llm", fake)
    _salty_dinners(db_session, member.id)
    first = svc.all_advice(db_session, member.id, now=_at())
    assert (first.action.key, first.action_source) == ("tip_sodium", "rules")
    svc.all_advice(db_session, member.id, now=_at(hours=0.5))
    assert fake.calls == 1
    fake.fail = False
    assert svc.all_advice(db_session, member.id, now=_at(hours=1.1)).action_source == "llm"


def test_endpoint_all(client, monkeypatch):
    monkeypatch.setattr(ai, "_call_llm", _FakeAI(fail=True))
    email = f"all-api-{uuid.uuid4().hex[:8]}@oncare.com"
    client.post("/v1/auth/register", json={"email": email, "password": "oncare123", "name": "조언"})
    token = client.post("/v1/auth/login", data={"username": email, "password": "oncare123"}).json()["access_token"]
    body = client.get("/v1/diet/advice?period=all", headers={"Authorization": f"Bearer {token}"}).json()
    assert body["analysis_key"] == "all_few_records"
    assert body["message"] == "최근 4주 기록이 0일이에요. 7일이 넘으면 흐름을 짚어 드릴게요."
