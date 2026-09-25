"""끼니별 추천 메뉴 리스트 — 생성·보관·재생성·폴백. (#2250)

AI 는 붙이지 않고 `_call_llm` 을 가짜로 바꿔 결정론적으로 본다. 보려는 것은 AI
품질이 아니라 계약이다:

1. 리스트는 늘 아침·점심·저녁 5개씩, 간식 3개이고 이름이 겹치지 않는다.
2. 없거나 28일이 지났거나 목표가 바뀌었거나 기록이 7일 쌓이면 다시 만든다.
3. 새 리스트는 이전 리스트의 메뉴를 넣지 않는다.
4. AI 가 실패하면 카탈로그로 채우고, 1시간 뒤에야 다시 시도한다.
"""
from __future__ import annotations

import json
import uuid
from datetime import datetime, timedelta

import pytest
from sqlalchemy import delete, select

from app.core import clock
from app.data import diet_menu_catalog as catalog
from app.services import diet_coach_inputs as inputs
from app.services import diet_menu_plan as svc

_EXPECTED_TOTAL = sum(catalog.SLOT_COUNTS.values())


def _llm_payload(prefix: str = "메뉴", tag: str = "protein_high") -> str:
    items = []
    for slot, n in catalog.SLOT_COUNTS.items():
        for i in range(n):
            items.append({
                "slot": slot, "name": f"{prefix}{slot[:2]}{i}", "tag": tag,
                "keyword": "고단백", "kcal": 400, "protein_g": 30, "sodium_mg": 500,
            })
    return json.dumps({"items": items}, ensure_ascii=False)


def _counts(plan) -> dict[str, int]:
    return {slot: len(plan.for_slot(slot)) for slot in catalog.SLOTS}


def _assert_shape(plan) -> None:
    assert _counts(plan) == catalog.SLOT_COUNTS
    names = [svc._norm(m.name) for m in plan.items]
    assert len(names) == len(set(names)) == _EXPECTED_TOTAL


# ── 순수 함수 ────────────────────────────────────────────────────────────


def test_rules_plan_fills_every_slot_without_duplicates():
    items = svc.rules_plan(lang="ko", needs=[], excluded=set())
    plan = svc.MenuPlan("x", "ko", "rules", items, 0, "", "")
    _assert_shape(plan)


def test_rules_plan_puts_urgent_tag_first_and_mixes_tags():
    items = svc.rules_plan(lang="ko", needs=[catalog.TAG_SODIUM_LOW], excluded=set())
    lunch = [m for m in items if m.slot == catalog.SLOT_LUNCH]
    assert lunch[0].tag == catalog.TAG_SODIUM_LOW
    # 한 태그로만 채우지 않는다.
    assert len({m.tag for m in lunch}) >= 3


def test_rules_plan_avoids_previous_menus_while_catalog_allows():
    first = svc.rules_plan(lang="ko", needs=[], excluded=set())
    excluded = {svc._norm(m.name) for m in first}
    second = svc.rules_plan(lang="ko", needs=[], excluded=excluded)
    main_slots = (catalog.SLOT_BREAKFAST, catalog.SLOT_LUNCH, catalog.SLOT_DINNER, catalog.SLOT_SNACK)
    for slot in main_slots:
        again = [m for m in second if m.slot == slot and svc._norm(m.name) in excluded]
        assert again == [], slot


def test_rules_plan_english_names_and_keywords():
    items = svc.rules_plan(lang="en", needs=[], excluded=set())
    assert all(m.name.isascii() and m.keyword.isascii() for m in items)


def test_parse_items_drops_bad_rows_and_fills_from_catalog():
    rows = [
        {"slot": "breakfast", "name": "귀리 죽", "tag": "fiber_high", "keyword": "식이섬유",
         "kcal": 300, "protein_g": 10, "sodium_mg": 200},
        # 겹치는 이름
        {"slot": "lunch", "name": "귀리  죽", "tag": "fiber_high", "keyword": "x",
         "kcal": 300, "protein_g": 10, "sodium_mg": 200},
        # 모르는 끼니·태그
        {"slot": "lateNight", "name": "라면", "tag": "fiber_high", "kcal": 500, "protein_g": 10, "sodium_mg": 1800},
        {"slot": "dinner", "name": "스테이크", "tag": "tasty", "kcal": 500, "protein_g": 40, "sodium_mg": 500},
        # 이름이 너무 길다
        {"slot": "dinner", "name": "아주아주아주아주긴이름의메뉴입니다", "tag": "protein_high",
         "kcal": 500, "protein_g": 40, "sodium_mg": 500},
        # 단위를 헷갈린 값
        {"slot": "dinner", "name": "소금구이", "tag": "protein_high", "kcal": 500, "protein_g": 40, "sodium_mg": 9000},
        # 이전 리스트에 있던 메뉴
        {"slot": "dinner", "name": "옛 메뉴", "tag": "protein_high", "kcal": 500, "protein_g": 40, "sodium_mg": 500},
        # 키워드가 길면 태그 기본 키워드
        {"slot": "snack", "name": "두유", "tag": "sugar_low", "keyword": "당이 적은 음료라서 좋아요",
         "kcal": 90, "protein_g": 7, "sodium_mg": 90},
    ]
    items = svc.parse_items(
        json.dumps({"items": rows}, ensure_ascii=False),
        lang="ko", needs=[], excluded={svc._norm("옛 메뉴")},
    )
    plan = svc.MenuPlan("x", "ko", "llm", items, 0, "", "")
    _assert_shape(plan)
    names = [m.name for m in items]
    assert "귀리 죽" in names
    for dropped in ("라면", "스테이크", "소금구이", "옛 메뉴"):
        assert dropped not in names
    soy = next(m for m in items if m.name == "두유")
    assert soy.keyword == "저당"


def test_parse_items_accepts_code_fence_and_rejects_empty():
    fenced = "```json\n" + _llm_payload() + "\n```"
    items = svc.parse_items(fenced, lang="ko", needs=[], excluded=set())
    assert len(items) == _EXPECTED_TOTAL
    with pytest.raises(ValueError):
        svc.parse_items('{"items": []}', lang="ko", needs=[], excluded=set())


def test_needs_follow_recent_averages():
    targets = inputs.DietTargets(calories=2000, protein_g=80, sodium_mg=2000, sugar_g=50)
    empty = inputs.DietDigest(0, 0, 0, 0, 0, {}, [])
    assert svc.needs_of(empty, targets) == []
    salty = inputs.DietDigest(10, 2300, 50, 2600, 20, {}, [])
    assert svc.needs_of(salty, targets) == [
        catalog.TAG_SODIUM_LOW, catalog.TAG_PROTEIN_HIGH, catalog.TAG_CALORIE_LOW,
    ]


def test_targets_use_personal_values_then_weight_then_default():
    class P:
        daily_calories = 1800
        daily_protein_g = None
        daily_sodium_mg = None
        daily_sugar_g = 40
        weight_kg = 70.0

    t = inputs.targets_of(P())
    assert (t.calories, t.protein_g, t.sodium_mg, t.sugar_g) == (1800, 84, 2000, 40)
    P.weight_kg = None
    assert inputs.targets_of(P()).protein_g == inputs.DEFAULT_PROTEIN_G
    P.daily_protein_g = 110
    assert inputs.targets_of(P()).protein_g == 110
    assert inputs.targets_of(None).calories == inputs.DEFAULT_CALORIES


def test_prompt_carries_trainer_notes_previous_menus_and_language():
    targets = inputs.DietTargets(2000, 80, 2000, 50)
    recent = inputs.DietDigest(0, 0, 0, 0, 0, {}, [])
    prev = (svc.PlanMenu("dinner", "구운 고등어 정식", "protein_high", "고단백", 600, 32, 650),)
    system, user = svc.build_prompt(
        lang="en", profile=None, targets=targets, recent=recent, needs=[],
        notes=["저녁 탄수화물은 줄여 주세요"], previous=prev,
    )
    assert "트레이너: 저녁 탄수화물은 줄여 주세요" in user
    assert "- 구운 고등어 정식" in user
    assert "영어(English)" in system
    assert "상충" in system  # 트레이너 조언과 상충하지 않는다(대원칙)


# ── DB ───────────────────────────────────────────────────────────────────


@pytest.fixture
def member(db_session):
    from app.core.security import hash_password
    from app.models.models import DietEntry, DietMenuPlan, HealthProfile, User

    user = User(
        id=f"user-{uuid.uuid4().hex[:12]}", email=f"menuplan-{uuid.uuid4().hex[:8]}@example.com",
        name="메뉴 리스트", hashed_password=hash_password("pw!"), role="member",
    )
    db_session.add(user)
    db_session.add(HealthProfile(user_id=user.id, daily_protein_g=90))
    db_session.commit()
    yield user
    db_session.rollback()
    db_session.execute(delete(DietMenuPlan).where(DietMenuPlan.user_id == user.id))
    db_session.execute(delete(DietEntry).where(DietEntry.user_id == user.id))
    db_session.execute(delete(HealthProfile).where(HealthProfile.user_id == user.id))
    db_session.execute(delete(User).where(User.id == user.id))
    db_session.commit()


class _FakeLLM:
    def __init__(self, payloads=None, fail=False):
        self.calls = 0
        self.fail = fail
        self.payloads = list(payloads or [])
        self.prompts: list[tuple[str, str]] = []

    def __call__(self, system: str, user: str) -> str:
        self.calls += 1
        self.prompts.append((system, user))
        if self.fail:
            raise RuntimeError("키 없음")
        return self.payloads.pop(0) if self.payloads else _llm_payload(f"메뉴{self.calls}-")


def _now() -> datetime:
    return datetime(2026, 9, 21, 12, 0, tzinfo=clock.SEOUL)


def _add_days(db_session, user_id: str, start, n: int) -> None:
    from app.models.models import DietEntry

    for i in range(n):
        db_session.add(DietEntry(
            id=f"diet-{uuid.uuid4().hex[:12]}", user_id=user_id,
            date=(start + timedelta(days=i)).isoformat(), meal_type="lunch",
            foods_json=json.dumps([{"name": "김치찌개", "calories": 600}], ensure_ascii=False),
            total_calories=600, protein_g=20, sodium_mg=1800, sugar_g=5,
        ))
    db_session.commit()


def test_first_plan_without_records_is_made_and_kept(db_session, member, monkeypatch):
    fake = _FakeLLM()
    monkeypatch.setattr(svc, "_call_llm", fake)
    now = _now()

    plan = svc.get_plan(db_session, member.id, now=now)
    assert plan.source == "llm"
    assert plan.basis_days == 0
    assert plan.expires_on == (now.date() + timedelta(days=28)).isoformat()
    _assert_shape(plan)

    again = svc.get_plan(db_session, member.id, now=now + timedelta(days=27))
    assert again.id == plan.id
    assert fake.calls == 1


def test_expired_plan_is_remade_without_previous_menus(db_session, member, monkeypatch):
    first_payload = _llm_payload("첫")
    # 두 번째 응답이 첫 리스트를 그대로 되풀이해도, 이전 메뉴는 빠지고 카탈로그가 채운다.
    fake = _FakeLLM([first_payload, first_payload])
    monkeypatch.setattr(svc, "_call_llm", fake)
    now = _now()

    first = svc.get_plan(db_session, member.id, now=now)
    second = svc.get_plan(db_session, member.id, now=now + timedelta(days=28))
    assert second.id != first.id
    _assert_shape(second)
    first_names = {svc._norm(m.name) for m in first.items}
    assert not first_names & {svc._norm(m.name) for m in second.items}
    assert "[이전 추천]" in fake.prompts[1][1] and first.items[0].name in fake.prompts[1][1]


def test_goal_change_remakes_plan(db_session, member, monkeypatch):
    from app.models.models import HealthProfile

    fake = _FakeLLM()
    monkeypatch.setattr(svc, "_call_llm", fake)
    now = _now()
    first = svc.get_plan(db_session, member.id, now=now)

    profile = db_session.scalar(select(HealthProfile).where(HealthProfile.user_id == member.id))
    profile.daily_protein_g = 120
    db_session.commit()
    second = svc.get_plan(db_session, member.id, now=now + timedelta(hours=1))
    assert second.id != first.id

    # 목표 칩 순서만 바뀐 것은 목표 변경이 아니다.
    profile.conditions = "체중 감량, 근력 향상"
    db_session.commit()
    third = svc.get_plan(db_session, member.id, now=now + timedelta(hours=2))
    profile.conditions = "근력 향상, 체중 감량"
    db_session.commit()
    fourth = svc.get_plan(db_session, member.id, now=now + timedelta(hours=3))
    assert fourth.id == third.id


def test_plan_made_before_seven_days_is_remade_once_records_pile_up(db_session, member, monkeypatch):
    fake = _FakeLLM()
    monkeypatch.setattr(svc, "_call_llm", fake)
    now = _now()
    first = svc.get_plan(db_session, member.id, now=now)
    assert first.basis_days == 0

    _add_days(db_session, member.id, now.date() - timedelta(days=5), 6)
    assert svc.get_plan(db_session, member.id, now=now).id == first.id

    _add_days(db_session, member.id, now.date() - timedelta(days=6), 1)
    second = svc.get_plan(db_session, member.id, now=now)
    assert second.id != first.id
    assert second.basis_days == 7
    assert "김치찌개 7회" in fake.prompts[-1][1]
    # 한 번 다시 만든 뒤에는 더 만들지 않는다.
    assert svc.get_plan(db_session, member.id, now=now).id == second.id


def test_language_change_remakes_plan(db_session, member, monkeypatch):
    monkeypatch.setattr(svc, "_call_llm", _FakeLLM(fail=True))
    now = _now()
    ko = svc.get_plan(db_session, member.id, now=now, use_llm=False)
    en = svc.get_plan(db_session, member.id, now=now, lang="en", use_llm=False)
    assert en.id != ko.id and en.lang == "en"
    assert all(m.name.isascii() for m in en.items)


def test_llm_failure_falls_back_and_retries_after_an_hour(db_session, member, monkeypatch):
    from app.models.models import DietMenuPlan

    fake = _FakeLLM(fail=True)
    monkeypatch.setattr(svc, "_call_llm", fake)
    now = _now()

    plan = svc.get_plan(db_session, member.id, now=now)
    assert plan.source == "rules"
    _assert_shape(plan)
    row = db_session.get(DietMenuPlan, plan.id)
    assert row.retry_after is not None

    # 1시간이 안 됐으면 AI 를 다시 부르지 않는다.
    assert svc.get_plan(db_session, member.id, now=now + timedelta(minutes=59)).source == "rules"
    assert fake.calls == 1

    fake.fail = False
    retried = svc.get_plan(db_session, member.id, now=now + timedelta(minutes=61))
    assert fake.calls == 2
    assert retried.source == "llm"
    assert retried.id == plan.id  # 같은 리스트를 채워 넣는다(만료일이 밀리지 않는다)
    assert retried.expires_on == plan.expires_on
    db_session.refresh(row)
    assert row.retry_after is None


def test_without_llm_there_is_no_retry(db_session, member, monkeypatch):
    from app.models.models import DietMenuPlan

    fake = _FakeLLM()
    monkeypatch.setattr(svc, "_call_llm", fake)
    plan = svc.get_plan(db_session, member.id, now=_now(), use_llm=False)
    assert plan.source == "rules"
    assert db_session.get(DietMenuPlan, plan.id).retry_after is None
    assert fake.calls == 0


def test_only_the_previous_plan_is_kept(db_session, member, monkeypatch):
    from app.models.models import DietMenuPlan

    monkeypatch.setattr(svc, "_call_llm", _FakeLLM())
    now = _now()
    for i in range(3):
        svc.get_plan(db_session, member.id, now=now + timedelta(days=28 * i))
    rows = db_session.scalars(select(DietMenuPlan).where(DietMenuPlan.user_id == member.id)).all()
    assert len(rows) == 2


def test_trainer_notes_only_trainer_sent_recent_messages(db_session):
    from app.models.models import ChatMessage
    from app.services.trainer_service import get_member_trainer_id

    member_id = "user-7d4e9a2c5f18"  # 데모 김민수 — 담당 트레이너가 있다
    trainer_id = get_member_trainer_id(db_session, member_id)
    assert trainer_id is not None
    now = clock.now()
    marker = uuid.uuid4().hex[:6]
    rows = [
        ChatMessage(id=f"chat-{uuid.uuid4().hex[:12]}", trainer_id=trainer_id, member_id=member_id,
                    sender="trainer", body=f"저녁은 탄수화물을 줄여 주세요 {marker}", created_at=now),
        ChatMessage(id=f"chat-{uuid.uuid4().hex[:12]}", trainer_id=trainer_id, member_id=member_id,
                    sender="member", body=f"네 알겠어요 {marker}", created_at=now),
        ChatMessage(id=f"chat-{uuid.uuid4().hex[:12]}", trainer_id=trainer_id, member_id=member_id,
                    sender="trainer", body=f"옛 지시 {marker}", created_at=now - timedelta(days=20)),
    ]
    db_session.add_all(rows)
    db_session.commit()
    try:
        notes = inputs.trainer_notes(db_session, member_id)
        assert f"저녁은 탄수화물을 줄여 주세요 {marker}" in notes
        assert not any(f"네 알겠어요 {marker}" in n for n in notes)
        assert not any(f"옛 지시 {marker}" in n for n in notes)
    finally:
        for row in rows:
            db_session.delete(row)
        db_session.commit()
