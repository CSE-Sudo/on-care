"""식단 `이번 주` AI 맞춤 조언 — 규칙 한 줄 + AI 한 문장, 하루 한 번. (#2253)

보는 것:
1. 월·화이고 이번 주 기록이 이틀 미만이면 지난주를 돌아본다(운동 조언과 같은 규칙).
2. 끼니 습관(아침 건너뜀) → 집중 목표(가장 많이 넘긴 영양소) → 칭찬 순으로 하나.
3. AI 문장에는 규칙이 계산하지 않은 수치가 없고 길이 한도 안이다. 어기면 다시 받고,
   그래도 안 되면 규칙 대체 문장이다.
4. 한 번 만든 조언은 그날 내내 두고, AI 가 실패했으면 1시간 뒤 다시 만든다.
"""
from __future__ import annotations

import json
import uuid
from datetime import date, datetime, time, timedelta

import pytest
from sqlalchemy import delete, func, select

from app.core import clock
from app.services import diet_advice_copy as copy
from app.services import diet_ai_sentence as ai
from app.services import diet_coach_inputs as inputs
from app.services import diet_week_advice as svc

TARGETS = inputs.DietTargets(calories=2000, protein_g=90, sodium_mg=2000, sugar_g=50)
MON = date(2026, 9, 21)  # 월요일


# ── 기간 경계 ────────────────────────────────────────────────────────────


def test_week_window_looks_back_early_in_the_week():
    last_week = {MON - timedelta(days=3)}
    assert svc.week_window(MON, last_week) == ("last", MON - timedelta(days=7), MON - timedelta(days=1))
    tue = MON + timedelta(days=1)
    assert svc.week_window(tue, last_week | {MON})[0] == "last"
    # 화요일에 이번 주 이틀을 적었으면 이번 주다.
    assert svc.week_window(tue, last_week | {MON, tue}) == ("this", MON, tue)
    # 지난주 기록이 없으면 돌아볼 것이 없다.
    assert svc.week_window(MON, set())[0] == "this"
    # 수요일부터는 이번 주다.
    wed = MON + timedelta(days=2)
    assert svc.week_window(wed, last_week) == ("this", MON, wed)


# ── 규칙 한 줄 ───────────────────────────────────────────────────────────


def _rec(day, *, slots=("breakfast", "lunch", "dinner"), kcal=1800, protein=90, sodium=1500, sugar=30):
    r = svc.DayRecord(day=day, kcal=kcal, protein_g=protein, sodium_mg=sodium, sugar_g=sugar)
    r.slots = set(slots)
    r.meals = [(s, [f"{s} 메뉴"], 500, 20, 500, 10) for s in slots]
    return r


def _find(records, today=None, at=time(20)):
    today = today or MON + timedelta(days=6)
    return svc.find({r.day: r for r in records}, TARGETS, "this", today=today, now_time=at)


def test_skipped_breakfast_with_afternoon_snacks_comes_first():
    days = [MON + timedelta(days=i) for i in range(5)]
    records = [_rec(d, slots=("lunch", "dinner", "snack")) for d in days[:3]]
    records += [_rec(d, sodium=2600) for d in days[3:]]
    f = _find(records)
    assert f.kind == "breakfast"
    assert (f.analysis.key, f.analysis.params) == (
        "week_skip_breakfast_snack", {"scope": "this", "days": 3, "snack_days": 3},
    )
    assert f.analysis.text == "이번 주 아침 거른 3일 중 **3일** 간식을 드셨어요."


def test_skipped_breakfast_without_snacks():
    records = [_rec(MON + timedelta(days=i), slots=("lunch", "dinner")) for i in range(3)]
    assert _find(records).analysis.key == "week_skip_breakfast"


def test_today_before_eleven_is_not_a_skipped_breakfast():
    today = MON + timedelta(days=2)
    records = [_rec(MON + timedelta(days=i), slots=("lunch",)) for i in range(3)]
    assert _find(records, today=today, at=time(10)).kind != "breakfast"
    assert _find(records, today=today, at=time(12)).kind == "breakfast"


def test_focus_picks_the_most_frequent_and_prefers_excess_on_ties():
    days = [MON + timedelta(days=i) for i in range(6)]
    records = [_rec(d, sodium=2500) for d in days[:2]] + [_rec(d, protein=40) for d in days[2:5]]
    f = _find(records)
    assert (f.kind, f.analysis.params["days"]) == ("protein", 3)
    tie = [_rec(d, sodium=2500) for d in days[:2]] + [_rec(d, protein=40) for d in days[2:4]]
    assert _find(tie).kind == "sodium"


def test_one_day_over_is_not_praised():
    records = [_rec(MON + timedelta(days=i)) for i in range(4)] + [_rec(MON + timedelta(days=4), sugar=80)]
    f = _find(records)
    assert (f.kind, f.analysis.params["days"]) == ("sugar", 1)


def test_praise_when_every_day_is_within():
    f = _find([_rec(MON + timedelta(days=i)) for i in range(4)])
    assert (f.kind, f.analysis.key) == ("good", "week_good")


def test_record_lines_show_the_saltiest_meals_first():
    r = _rec(MON, sodium=3000)
    r.meals = [("lunch", ["짬뽕"], 800, 25, 2800, 8), ("dinner", ["샐러드"], 400, 20, 300, 4)]
    f = svc.Finding("sodium", copy.line("week_focus_sodium", scope="this", days=1), "", (MON,))
    lines = svc.record_lines(f, {MON: r})
    assert lines[0].startswith("월 점심: 짬뽕")


def test_every_week_line_fits_with_its_fallback_tip():
    """규칙 한 줄과 대체 문장, 규칙 한 줄과 가장 짧은 AI 문장이 45자 안이다."""
    worst = {
        "breakfast": copy.line("week_skip_breakfast_snack", scope="this", days=7, snack_days=7),
        "sodium": copy.line("week_focus_sodium", scope="this", days=7),
        "calorie": copy.line("week_focus_calorie", scope="this", days=7),
        "sugar": copy.line("week_focus_sugar", scope="this", days=7),
        "protein": copy.line("week_focus_protein", scope="this", days=7),
    }
    for kind, analysis in worst.items():
        tip = copy.line("tip_breakfast" if kind == "breakfast" else svc._FOCUS_TIPS[kind])
        assert len(copy.message(analysis, tip)) <= 45, kind
        assert ai.sentence_limit("ko", analysis.text) >= ai.MIN_SENTENCE["ko"]
    good = copy.message(copy.line("week_good", scope="last", days=7), copy.line("tip_keep"))
    assert len(good) <= 45


# ── AI 문장 검사 ─────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    ("text", "measure"),
    [
        ("짬뽕 국물은 반만, 건더기 위주로요.", False),
        ("생선·두부 메뉴를 주 3회 넣어 봐요.", False),
        ("달걀 2개를 더해 보세요.", False),
        ("Add 2 boiled eggs in the morning.", False),
        ("나트륨을 1,800mg 아래로 줄여요.", True),
        ("단백질 20g 을 채워요.", True),
        ("80% 만 드세요.", True),
        ("10분 걷기를 더해요.", True),
        ("Keep it under 500 kcal.", True),
    ],
)
def test_ai_sentence_may_not_carry_measures(text, measure):
    assert ai.has_measure(text) is measure


def test_ai_sentence_clean_and_length():
    assert ai.clean('```json\n{"sentence": "  \\"**연어**를 드세요\\"  "}\n```') == "**연어**를 드세요"
    # 짝이 안 맞는 굵은 표시는 뗀다.
    assert ai.clean('{"sentence": "**연어를 드세요"}') == "연어를 드세요"
    assert ai.valid("**연어**를 드세요.", 10)
    assert not ai.valid("아주 길고 긴 문장이라서 한도를 넘는 조언입니다.", 10)


def test_generate_retries_once_then_gives_up(monkeypatch):
    answers = iter(['{"sentence": "나트륨 1,800mg 이하로요"}', '{"sentence": "국물은 반만 드세요."}'])
    monkeypatch.setattr(ai, "_call_llm", lambda s, u: next(answers))
    kw = dict(lang="ko", analysis_text="이번 주 나트륨을 **3일** 넘겼어요.", finding="f",
              records=["월 점심: 짬뽕"], notes=[], goal="", metric="t")
    assert ai.generate(**kw) == "국물은 반만 드세요."

    bad = iter(['{"sentence": "1,800mg"}', '{"sentence": "2,000mg"}'])
    monkeypatch.setattr(ai, "_call_llm", lambda s, u: next(bad))
    assert ai.generate(**kw) is None

    def boom(s, u):
        raise RuntimeError("키 없음")

    monkeypatch.setattr(ai, "_call_llm", boom)
    assert ai.generate(**kw) is None


def test_prompt_carries_records_trainer_notes_and_language():
    system, user = ai.build_prompt(
        lang="en", limit=40, finding="이번 주 나트륨을 3일 넘겼다.",
        records=["월 점심: 짬뽕"], notes=["국물은 드시지 마세요"], goal="체중 감량",
    )
    assert "영어(English)" in system and "40자" in system and "상충" in system
    assert "- 월 점심: 짬뽕" in user and "트레이너: 국물은 드시지 마세요" in user


# ── DB ───────────────────────────────────────────────────────────────────


@pytest.fixture
def member(db_session):
    from app.core.security import hash_password
    from app.models.models import DietAdviceState, DietEntry, HealthProfile, User

    user = User(
        id=f"user-{uuid.uuid4().hex[:12]}", email=f"week-{uuid.uuid4().hex[:8]}@example.com",
        name="이번 주 조언", hashed_password=hash_password("pw!"), role="member",
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


def _eat(db_session, user_id, day, meal, *, name="밥", sodium=500, protein=30.0, kcal=600):
    from app.models.models import DietEntry

    db_session.add(DietEntry(
        id=f"diet-{uuid.uuid4().hex[:12]}", user_id=user_id, date=day.isoformat(),
        meal_type=meal, foods_json=json.dumps([{"name": name, "calories": kcal}], ensure_ascii=False),
        total_calories=kcal, protein_g=protein, sodium_mg=sodium, sugar_g=5,
    ))
    db_session.commit()


def _salty_week(db_session, user_id):
    for i in range(3):  # 월~수 저녁에 짬뽕
        day = MON + timedelta(days=i)
        _eat(db_session, user_id, day, "breakfast")
        _eat(db_session, user_id, day, "lunch")
        _eat(db_session, user_id, day, "dinner", name="짬뽕", sodium=2500)


def _thu(hour=19, days=0):
    return datetime(2026, 9, 24, hour, 0, tzinfo=clock.SEOUL) + timedelta(days=days)


class _FakeAI:
    def __init__(self, answer='{"sentence": "짬뽕 국물은 반만 드세요."}', fail=False):
        self.answer, self.fail, self.calls, self.prompts = answer, fail, 0, []

    def __call__(self, system, user):
        self.calls += 1
        self.prompts.append(user)
        if self.fail:
            raise RuntimeError("키 없음")
        return self.answer


def _states(db_session, user_id):
    from app.models.models import DietAdviceState

    return db_session.scalar(
        select(func.count()).select_from(DietAdviceState)
        .where(DietAdviceState.user_id == user_id, DietAdviceState.period == "week")
    )


def test_week_advice_names_the_cause_and_is_kept_for_the_day(db_session, member, monkeypatch):
    fake = _FakeAI()
    monkeypatch.setattr(ai, "_call_llm", fake)
    _salty_week(db_session, member.id)

    advice = svc.week_advice(db_session, member.id, now=_thu())
    assert advice.analysis.key == "week_focus_sodium"
    assert advice.analysis.params == {"scope": "this", "days": 3}
    assert (advice.action.key, advice.action.text, advice.action_source) == (
        None, "짬뽕 국물은 반만 드세요.", "llm",
    )
    assert "짬뽕" in fake.prompts[0]

    # 그날 안에서는 기록이 바뀌어도 다시 만들지 않는다.
    _eat(db_session, member.id, MON + timedelta(days=3), "dinner", sodium=2600)
    again = svc.week_advice(db_session, member.id, now=_thu(hour=22))
    assert again.analysis.params == {"scope": "this", "days": 3}
    assert fake.calls == 1

    # 다음 날 새로 만든다.
    tomorrow = svc.week_advice(db_session, member.id, now=_thu(days=1))
    assert tomorrow.analysis.params["days"] == 4
    assert fake.calls == 2


def test_week_advice_falls_back_and_retries_after_an_hour(db_session, member, monkeypatch):
    fake = _FakeAI(fail=True)
    monkeypatch.setattr(ai, "_call_llm", fake)
    _salty_week(db_session, member.id)

    first = svc.week_advice(db_session, member.id, now=_thu())
    assert (first.action.key, first.action_source) == ("tip_sodium", "rules")
    svc.week_advice(db_session, member.id, now=_thu() + timedelta(minutes=59))
    assert fake.calls == 1

    fake.fail = False
    retried = svc.week_advice(db_session, member.id, now=_thu() + timedelta(minutes=61))
    assert retried.action_source == "llm"
    assert fake.calls == 2
    assert _states(db_session, member.id) == 1


def test_empty_week_is_not_kept_and_praise_does_not_call_ai(db_session, member, monkeypatch):
    fake = _FakeAI()
    monkeypatch.setattr(ai, "_call_llm", fake)
    empty = svc.week_advice(db_session, member.id, now=_thu())
    assert (empty.analysis.key, empty.action.key) == ("week_empty", "week_empty_hint")
    assert _states(db_session, member.id) == 0

    for i in range(3):
        for meal in ("breakfast", "lunch", "dinner"):
            _eat(db_session, member.id, MON + timedelta(days=i), meal)
    good = svc.week_advice(db_session, member.id, now=_thu())
    assert (good.analysis.key, good.action.key) == ("week_good", "tip_keep")
    assert fake.calls == 0


def test_monday_looks_back_at_last_week(db_session, member, monkeypatch):
    monkeypatch.setattr(ai, "_call_llm", _FakeAI())
    last_week = MON - timedelta(days=7)
    for i in range(3):
        _eat(db_session, member.id, last_week + timedelta(days=i), "dinner", name="짬뽕", sodium=2500)
    advice = svc.week_advice(db_session, member.id, now=datetime(2026, 9, 21, 9, tzinfo=clock.SEOUL))
    assert advice.analysis.params["scope"] == "last"
    assert (advice.from_date, advice.to_date) == (last_week.isoformat(), (MON - timedelta(days=1)).isoformat())
    assert advice.analysis.text.startswith("지난주")


def test_endpoint_week(client, monkeypatch):
    monkeypatch.setattr(ai, "_call_llm", _FakeAI(fail=True))
    email = f"week-api-{uuid.uuid4().hex[:8]}@oncare.com"
    client.post("/v1/auth/register", json={"email": email, "password": "oncare123", "name": "조언"})
    token = client.post("/v1/auth/login", data={"username": email, "password": "oncare123"}).json()["access_token"]
    body = client.get("/v1/diet/advice?period=week", headers={"Authorization": f"Bearer {token}"}).json()
    assert body["analysis_key"] == "week_empty"
    assert body["action_key"] == "week_empty_hint"
    assert body["message"] == "이번 주 식단 기록이 아직 없어요. 한 끼만 남겨도 흐름이 보여요."
