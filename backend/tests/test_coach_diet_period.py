"""AI 코칭이 이번 주·이번 달 누적 식단 데이터를 참고하는지 (#933).

기존 코칭(`coach_service._diet_suggestion`, `domain_coaches.diet_coach`, `coach/chat.py`)
은 오늘 하루 기록 또는 벡터 검색으로 우연히 걸리는 개별 기록만 봤다. 이 테스트는
- 기간 집계(`diet_service.period_stats`)가 하루 여러 끼니를 정확히 합쳐 평균 내는지
- 규칙 기반 폴백이 오늘은 괜찮아도 이번 주 패턴을 짚어내는지 (그리고 오늘 자체가
  비어 있거나 초과일 때는 기존 동작을 그대로 유지하는지)
- RAG 코치·챗봇이 그 요약을 실제 LLM 프롬프트에 실어 보내는지
를 확인한다.
"""
from __future__ import annotations

import uuid
from datetime import datetime

import pytest

from app.core import clock
from app.models.models import DietEntry, User
from app.services import coach_service, diet_service
from app.services.coach import chat as coach_chat
from app.services.coach import domain_coaches
from app.services.coach.llm_base import LLMResult

#: 요일이 갈리는 실제 실행일에 기대지 않도록 시각을 고정한다(#557 류 회귀 방지).
#: 2026-03-12 은 목요일 — 월~목 나흘이 "이번 주"에 들어와, 사흘을 초과일로 만들고도
#: 오늘 하루는 초과가 아닌 시나리오를 구성할 수 있다.
_FROZEN_TODAY = datetime(2026, 3, 12, 9, 0, tzinfo=clock.SEOUL)


@pytest.fixture
def frozen_thursday(monkeypatch):
    monkeypatch.setattr(clock, "now", lambda: _FROZEN_TODAY)


def _make_user(db_session) -> str:
    user_id = f"diet-period-{uuid.uuid4().hex[:12]}"
    db_session.add(
        User(
            id=user_id, email=f"{user_id}@example.com", name="기간 테스트",
            hashed_password="",
        )
    )
    db_session.flush()
    return user_id


def _add_entry(
    db_session, user_id: str, date: str, *, calories: int, sodium: int, sugar: float,
) -> None:
    db_session.add(
        DietEntry(
            id=f"{user_id}-{date}-{uuid.uuid4().hex[:8]}",
            user_id=user_id, date=date, meal_type="lunch",
            total_calories=calories, sodium_mg=sodium, sugar_g=sugar,
        )
    )
    db_session.flush()


# ---- diet_service.period_stats (순수 집계) ----

def test_period_stats_averages_only_days_with_entries(db_session):
    user_id = _make_user(db_session)
    # 하루에 여러 끼니가 있으면 합쳐서 하루 값이 되어야 한다.
    _add_entry(db_session, user_id, "2024-05-01", calories=400, sodium=900, sugar=5.0)
    _add_entry(db_session, user_id, "2024-05-01", calories=300, sodium=1000, sugar=3.0)
    _add_entry(db_session, user_id, "2024-05-02", calories=300, sodium=500, sugar=2.0)

    stats = diet_service.period_stats(db_session, user_id, "2024-05-01", "2024-05-02")

    assert stats.days_logged == 2
    assert stats.days_over_sodium == 0  # 05-01 합계 1900 도, 05-02 500 도 미초과
    assert stats.avg_calories == 500  # (700+300)/2
    assert stats.avg_sodium_mg == 1200  # (1900+500)/2
    assert stats.avg_sugar_g == 5.0  # (8.0+2.0)/2


def test_period_stats_empty_range_is_reported_as_empty(db_session):
    user_id = _make_user(db_session)
    stats = diet_service.period_stats(db_session, user_id, "2024-05-01", "2024-05-02")
    assert stats.empty is True
    assert stats.days_logged == 0


# ---- coach_service.diet_period_context ----

def test_diet_period_context_summarizes_week_and_month(db_session, frozen_thursday):
    user_id = _make_user(db_session)
    _add_entry(db_session, user_id, "2026-03-02", calories=1500, sodium=1000, sugar=30.0)
    _add_entry(db_session, user_id, "2026-03-09", calories=1800, sodium=2500, sugar=40.0)
    _add_entry(db_session, user_id, "2026-03-10", calories=1700, sodium=2200, sugar=35.0)
    _add_entry(db_session, user_id, "2026-03-11", calories=1600, sodium=2300, sugar=38.0)
    _add_entry(db_session, user_id, "2026-03-12", calories=1900, sodium=800, sugar=20.0)  # 오늘

    text = coach_service.diet_period_context(db_session, user_id)

    assert "이번 주 4일 기록" in text
    assert "초과 3일" in text
    assert "평균 나트륨 1950mg" in text
    assert "이번 달 5일 기록" in text
    assert "평균 칼로리 1700kcal" in text
    assert "평균 당류 32.6g" in text


def test_diet_period_context_empty_when_no_diet_history(db_session, frozen_thursday):
    user_id = _make_user(db_session)
    assert coach_service.diet_period_context(db_session, user_id) == ""


# ---- coach_service._diet_suggestion (규칙 기반 폴백) ----

def test_diet_suggestion_flags_repeated_weekly_sodium_excess(db_session, frozen_thursday):
    """오늘은 괜찮아도 이번 주 대부분이 초과였으면 그 패턴을 짚어준다."""
    user_id = _make_user(db_session)
    _add_entry(db_session, user_id, "2026-03-09", calories=1800, sodium=2500, sugar=40.0)
    _add_entry(db_session, user_id, "2026-03-10", calories=1700, sodium=2200, sugar=35.0)
    _add_entry(db_session, user_id, "2026-03-11", calories=1600, sodium=2300, sugar=38.0)
    _add_entry(db_session, user_id, "2026-03-12", calories=1900, sodium=800, sugar=20.0)  # 오늘, 미초과

    suggestion = coach_service._diet_suggestion(db_session, user_id)

    assert suggestion.title == "이번 주 나트륨이 계속 높았어요"
    assert "4일 중 3일" in suggestion.body


def test_diet_suggestion_ignores_a_short_or_mild_weekly_pattern(db_session, frozen_thursday):
    """초과일이 기준(3일) 미만이면 기존처럼 '식단 균형이 좋아요' 로 남는다."""
    user_id = _make_user(db_session)
    _add_entry(db_session, user_id, "2026-03-10", calories=1700, sodium=2200, sugar=35.0)
    _add_entry(db_session, user_id, "2026-03-11", calories=1600, sodium=1200, sugar=20.0)
    _add_entry(db_session, user_id, "2026-03-12", calories=1900, sodium=800, sugar=20.0)  # 오늘

    suggestion = coach_service._diet_suggestion(db_session, user_id)

    assert suggestion.title == "식단 균형이 좋아요"


def test_diet_suggestion_unaffected_when_today_has_no_records(db_session, frozen_thursday):
    """오늘 기록이 없으면 이번 주가 나빠도 '오늘 식단을 기록해 보세요' 가 그대로 나온다."""
    user_id = _make_user(db_session)
    _add_entry(db_session, user_id, "2026-03-09", calories=1800, sodium=2500, sugar=40.0)
    _add_entry(db_session, user_id, "2026-03-10", calories=1700, sodium=2200, sugar=35.0)
    _add_entry(db_session, user_id, "2026-03-11", calories=1600, sodium=2300, sugar=38.0)
    # 2026-03-12(오늘) 기록 없음

    suggestion = coach_service._diet_suggestion(db_session, user_id)

    assert suggestion.title == "오늘 식단을 기록해 보세요"


def test_diet_suggestion_unaffected_when_today_itself_exceeds(db_session, frozen_thursday):
    """오늘 자체가 초과면 주간 패턴과 무관하게 기존 '오늘' 경고가 그대로 나온다."""
    user_id = _make_user(db_session)
    _add_entry(db_session, user_id, "2026-03-12", calories=2000, sodium=2600, sugar=50.0)  # 오늘, 초과

    suggestion = coach_service._diet_suggestion(db_session, user_id)

    assert suggestion.title == "나트륨 섭취가 많아요"


# ---- domain_coaches._rag_suggestion: extra_context 만으로도 LLM 을 태운다 ----

def test_rag_suggestion_falls_back_when_context_and_period_summary_are_both_empty(
    monkeypatch,
):
    fallback = _dummy_suggestion()
    monkeypatch.setattr(domain_coaches, "retrieve_context", lambda *a, **k: "")

    def _boom(*_a, **_k):
        raise AssertionError("근거가 전혀 없으면 LLM 을 부르면 안 된다")

    monkeypatch.setattr(domain_coaches, "get_coach_llm", _boom)

    result = domain_coaches._rag_suggestion(
        None, "user-x", domain="diet", system_prompt="sys",
        query="q", tag="diet", title="t", fallback=fallback, extra_context="",
    )

    assert result is fallback


def test_rag_suggestion_uses_llm_when_only_period_summary_is_present(monkeypatch):
    """벡터 검색이 하나도 안 걸려도, 계산된 기간 요약만으로 LLM 코칭을 만든다."""
    fallback = _dummy_suggestion()
    monkeypatch.setattr(domain_coaches, "retrieve_context", lambda *a, **k: "")

    captured: dict[str, str] = {}

    class _StubLLM:
        def generate(self, system_prompt, user_prompt):
            captured["prompt"] = user_prompt
            return LLMResult(text="이번 주 나트륨이 높았으니 이번 주말엔 싱겁게 드세요.", model="stub")

    monkeypatch.setattr(domain_coaches, "get_coach_llm", lambda: _StubLLM())

    result = domain_coaches._rag_suggestion(
        None, "user-x", domain="diet", system_prompt="sys",
        query="q", tag="diet", title="오늘의 식단 코칭", fallback=fallback,
        extra_context="[이번 주·이번 달 식단 요약]\n- 이번 주 4일 기록, 나트륨 권장량(2000mg) 초과 3일",
    )

    assert result is not fallback
    assert "이번 주 나트륨이 높았으니" in result.body
    assert "이번 주 4일 기록" in captured["prompt"]


def test_diet_coach_carries_the_period_summary_into_the_llm_prompt(
    db_session, frozen_thursday, monkeypatch,
):
    """DB → diet_period_context → diet_coach 전체 배선이 이어지는지."""
    user_id = _make_user(db_session)
    _add_entry(db_session, user_id, "2026-03-09", calories=1800, sodium=2500, sugar=40.0)
    _add_entry(db_session, user_id, "2026-03-10", calories=1700, sodium=2200, sugar=35.0)
    _add_entry(db_session, user_id, "2026-03-11", calories=1600, sodium=2300, sugar=38.0)
    _add_entry(db_session, user_id, "2026-03-12", calories=1900, sodium=800, sugar=20.0)

    # 개인 RAG 문서가 하나도 안 걸리는 상황을 흉내낸다 — 그래도 기간 요약이
    # 있으니 폴백이 아니라 LLM 경로로 가야 한다.
    monkeypatch.setattr(domain_coaches, "retrieve_context", lambda *a, **k: "")

    captured: dict[str, str] = {}

    class _StubLLM:
        def generate(self, system_prompt, user_prompt):
            captured["prompt"] = user_prompt
            return LLMResult(text="이번 주 나트륨이 계속 높았어요. 주말엔 싱겁게 드세요.", model="stub")

    monkeypatch.setattr(domain_coaches, "get_coach_llm", lambda: _StubLLM())

    suggestion = domain_coaches.diet_coach(db_session, user_id)

    assert suggestion.body == "이번 주 나트륨이 계속 높았어요. 주말엔 싱겁게 드세요."
    assert "이번 주 4일 기록" in captured["prompt"]
    assert "초과 3일" in captured["prompt"]


def test_diet_coach_never_lets_ai_override_when_today_has_no_records(
    db_session, frozen_thursday, monkeypatch,
):
    """오늘 기록이 없으면 RAG/LLM 경로를 아예 타지 않는다 — 일반론으로 덮이면 안 된다(#933)."""
    user_id = _make_user(db_session)
    # 이번 주 기록이 있어도(기간 요약이 비어 있지 않아도) 오늘 기록이 없으면
    # 우선순위가 그대로 이겨야 한다.
    _add_entry(db_session, user_id, "2026-03-09", calories=1800, sodium=2500, sugar=40.0)

    monkeypatch.setattr(
        domain_coaches, "retrieve_context",
        lambda *a, **k: pytest.fail("일일 우선 상황에서는 검색조차 하면 안 된다"),
    )
    monkeypatch.setattr(
        domain_coaches, "get_coach_llm",
        lambda: pytest.fail("일일 우선 상황에서는 LLM 을 부르면 안 된다"),
    )

    suggestion = domain_coaches.diet_coach(db_session, user_id)

    assert suggestion.title == "오늘 식단을 기록해 보세요"


def test_diet_coach_never_lets_ai_override_when_today_sodium_exceeds(
    db_session, frozen_thursday, monkeypatch,
):
    """오늘 나트륨이 초과면 RAG/LLM 경로를 아예 타지 않는다(#933)."""
    user_id = _make_user(db_session)
    _add_entry(db_session, user_id, "2026-03-12", calories=2000, sodium=2600, sugar=50.0)

    monkeypatch.setattr(
        domain_coaches, "retrieve_context",
        lambda *a, **k: pytest.fail("일일 우선 상황에서는 검색조차 하면 안 된다"),
    )
    monkeypatch.setattr(
        domain_coaches, "get_coach_llm",
        lambda: pytest.fail("일일 우선 상황에서는 LLM 을 부르면 안 된다"),
    )

    suggestion = domain_coaches.diet_coach(db_session, user_id)

    assert suggestion.title == "나트륨 섭취가 많아요"


def test_diet_coach_checks_today_priority_only_once(
    db_session, frozen_thursday, monkeypatch,
):
    """오늘 우선 여부는 diet_coach 한 번 호출에서 딱 한 번만 조회한다.

    두 번 조회하면(예: 폴백 계산이 따로 다시 물으면) 그 사이 새 식단 기록이
    들어와 두 조회가 서로 다른 결과를 낼 수 있다(TOCTOU) — 첫 조회는 "정상"
    으로 보고 RAG 를 태웠는데 두 번째 조회가 "초과"를 반환하면, 성공한 RAG
    응답이 그 초과 경고를 조용히 덮는다.
    """
    user_id = _make_user(db_session)
    _add_entry(db_session, user_id, "2026-03-12", calories=1900, sodium=800, sugar=20.0)

    calls: list[str] = []
    original = coach_service._diet_today_priority

    def _counting(db, uid):
        calls.append(uid)
        return original(db, uid)

    monkeypatch.setattr(domain_coaches, "_diet_today_priority", _counting)
    monkeypatch.setattr(domain_coaches, "retrieve_context", lambda *a, **k: "")

    class _StubLLM:
        def generate(self, system_prompt, user_prompt):
            return LLMResult(text="괜찮은 하루였어요.", model="stub")

    monkeypatch.setattr(domain_coaches, "get_coach_llm", lambda: _StubLLM())

    domain_coaches.diet_coach(db_session, user_id)

    assert len(calls) == 1, f"오늘 우선 여부가 {len(calls)}번 조회됨: {calls}"


def test_rag_suggestion_falls_back_when_extra_context_itself_raises(monkeypatch):
    """extra_context 콜러블이 실패해도(예: 기간 요약 DB 조회 오류) 규칙 폴백으로 빠져야 한다."""
    fallback = _dummy_suggestion()
    monkeypatch.setattr(domain_coaches, "retrieve_context", lambda *a, **k: "")
    monkeypatch.setattr(
        domain_coaches, "get_coach_llm",
        lambda: pytest.fail("extra_context 실패 시 LLM 을 부르면 안 된다"),
    )

    def _boom() -> str:
        raise RuntimeError("기간 집계 쿼리 실패")

    result = domain_coaches._rag_suggestion(
        None, "user-x", domain="diet", system_prompt="sys",
        query="q", tag="diet", title="t", fallback=fallback, extra_context=_boom,
    )

    assert result is fallback


def test_diet_coach_falls_back_when_period_summary_query_fails(
    db_session, frozen_thursday, monkeypatch,
):
    """diet_period_context 내부 쿼리가 죽어도 전체 코칭 카드가 500 으로 죽지 않는다."""
    user_id = _make_user(db_session)
    _add_entry(db_session, user_id, "2026-03-12", calories=1900, sodium=800, sugar=20.0)

    monkeypatch.setattr(domain_coaches, "retrieve_context", lambda *a, **k: "")

    def _boom(db, uid):
        raise RuntimeError("DB 연결 끊김")

    monkeypatch.setattr(domain_coaches, "diet_period_context", _boom)
    monkeypatch.setattr(
        domain_coaches, "get_coach_llm",
        lambda: pytest.fail("기간 요약 조회가 실패하면 LLM 을 부르면 안 된다"),
    )

    suggestion = domain_coaches.diet_coach(db_session, user_id)

    # 오늘 기록만 있고 초과가 아니므로 규칙 기반 폴백은 '식단 균형이 좋아요'.
    assert suggestion.title == "식단 균형이 좋아요"


# ---- coach/chat.py: 챗봇도 같은 요약을 쓴다 ----

def test_chat_answer_carries_the_period_summary_into_the_llm_prompt(
    db_session, frozen_thursday, monkeypatch,
):
    user_id = _make_user(db_session)
    _add_entry(db_session, user_id, "2026-03-09", calories=1800, sodium=2500, sugar=40.0)
    _add_entry(db_session, user_id, "2026-03-10", calories=1700, sodium=2200, sugar=35.0)
    _add_entry(db_session, user_id, "2026-03-11", calories=1600, sodium=2300, sugar=38.0)
    _add_entry(db_session, user_id, "2026-03-12", calories=1900, sodium=800, sugar=20.0)

    monkeypatch.setattr(
        coach_chat, "retrieve", lambda *a, **k: {"personal": [], "public": []}
    )

    captured: dict[str, str] = {}

    class _StubLLM:
        def generate(self, system_prompt, user_prompt):
            captured["prompt"] = user_prompt
            return LLMResult(text="이번 주는 나트륨이 계속 높았어요.", model="stub")

    monkeypatch.setattr(coach_chat, "get_coach_llm", lambda: _StubLLM())

    text, _sources, _ = coach_chat.answer(db_session, user_id, "이번 주 식단 어땠어?")

    assert text == "이번 주는 나트륨이 계속 높았어요."
    assert "이번 주 4일 기록" in captured["prompt"]


def _dummy_suggestion():
    from app.schemas.misc_api import CoachSuggestion

    return CoachSuggestion(tag="diet", title="fallback", body="fallback body")
