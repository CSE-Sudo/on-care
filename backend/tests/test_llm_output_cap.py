"""LLM 출력 토큰 상한과 잘린 응답 처리. (#3032) DB 불필요.

* 어댑터 셋(Gemini·OpenAI·LiteLLM)이 모두 상한을 공급자 인자로 넘긴다 — Gemini 는
  `max_output_tokens`, OpenAI 호환은 `max_tokens`. 설정 `LLM_MAX_OUTPUT_TOKENS` 가
  천장이고 호출처는 더 작게만 줄 수 있다. 0 이면 넘기지 않는다.
* 공급자가 "길이 초과로 끊었다" 고 하면 `LLMResult.truncated` 가 참이다.
* JSON 을 받는 호출처는 잘린 응답을 계약 위반으로 보고 규칙형 폴백을 탄다.
* 호출처가 넘기는 상한은 설정보다 크지 않다.
"""
from __future__ import annotations

from types import SimpleNamespace

import pytest

from app.core import metrics
from app.core.config import get_settings
from app.services.coach import llm as llm_mod
from app.services.coach.llm_base import LLMResult, is_truncated, output_cap


@pytest.fixture
def ceiling(monkeypatch):
    s = get_settings()
    monkeypatch.setattr(s, "llm_max_output_tokens", 4096)
    return s


# ---------- 상한 계산 ----------


def test_output_cap_uses_the_setting_as_the_ceiling(ceiling, monkeypatch):
    assert output_cap() == 4096
    assert output_cap(512) == 512
    assert output_cap(10_000) == 4096
    monkeypatch.setattr(ceiling, "llm_max_output_tokens", 300)
    assert output_cap(512) == 300


def test_output_cap_is_off_when_the_setting_is_zero(ceiling, monkeypatch):
    monkeypatch.setattr(ceiling, "llm_max_output_tokens", 0)
    assert output_cap() is None
    assert output_cap(512) is None


def test_is_truncated_only_trusts_a_real_true():
    assert is_truncated(LLMResult(text="x", model="m", truncated=True))
    assert not is_truncated(LLMResult(text="x", model="m"))
    # 테스트 스텁처럼 필드가 없는 응답, 무엇이든 돌려주는 목 객체는 잘림이 아니다.
    assert not is_truncated(SimpleNamespace(text="x"))
    assert not is_truncated(SimpleNamespace(text="x", truncated="yes"))


@pytest.mark.parametrize(
    ("reason", "expected"),
    [
        (SimpleNamespace(name="MAX_TOKENS"), True),
        ("MAX_TOKENS", True),
        ("FinishReason.MAX_TOKENS", True),
        (SimpleNamespace(name="STOP"), False),
        ("STOP", False),
        (None, False),
    ],
)
def test_gemini_truncation_reads_the_finish_reason(reason, expected):
    resp = SimpleNamespace(candidates=[SimpleNamespace(finish_reason=reason)])
    assert llm_mod.gemini_truncated(resp) is expected


def test_gemini_truncation_is_false_without_candidates():
    assert llm_mod.gemini_truncated(SimpleNamespace(text="{}")) is False
    assert llm_mod.gemini_truncated(SimpleNamespace(candidates=None)) is False
    assert llm_mod.gemini_truncated(SimpleNamespace(candidates=[])) is False


# ---------- 어댑터 ----------


def _openai_like(cls, *, finish_reason: str = "stop"):
    sent: list[dict] = []

    def create(**kwargs):
        sent.append(kwargs)
        return SimpleNamespace(
            usage=None,
            choices=[
                SimpleNamespace(
                    message=SimpleNamespace(content='{"ok": true}'),
                    finish_reason=finish_reason,
                )
            ],
        )

    adapter = cls.__new__(cls)
    adapter._client = SimpleNamespace(
        chat=SimpleNamespace(completions=SimpleNamespace(create=create))
    )
    adapter._model = "test-model"
    return adapter, sent


@pytest.mark.parametrize("cls", [llm_mod.OpenAICoachLLM, llm_mod.LiteLLMCoachLLM])
def test_openai_compatible_adapters_send_max_tokens(ceiling, cls):
    adapter, sent = _openai_like(cls)

    adapter.generate("sys", "user")
    adapter.generate("sys", "user", json_mode=True, max_output_tokens=512)

    assert sent[0]["max_tokens"] == 4096
    assert sent[1]["max_tokens"] == 512
    assert sent[1]["response_format"] == {"type": "json_object"}


@pytest.mark.parametrize("cls", [llm_mod.OpenAICoachLLM, llm_mod.LiteLLMCoachLLM])
def test_openai_compatible_adapters_omit_max_tokens_when_off(ceiling, monkeypatch, cls):
    monkeypatch.setattr(ceiling, "llm_max_output_tokens", 0)
    adapter, sent = _openai_like(cls)
    adapter.generate("sys", "user", max_output_tokens=512)
    assert "max_tokens" not in sent[0]


@pytest.mark.parametrize("cls", [llm_mod.OpenAICoachLLM, llm_mod.LiteLLMCoachLLM])
def test_openai_compatible_adapters_flag_length_cut(ceiling, cls):
    cut, _ = _openai_like(cls, finish_reason="length")
    whole, _ = _openai_like(cls, finish_reason="stop")
    assert cut.generate("sys", "user").truncated is True
    assert whole.generate("sys", "user").truncated is False


def _gemini(*, finish_reason: object = "STOP"):
    configs: list[SimpleNamespace] = []

    def generate_content(*, model, contents, config):  # noqa: ARG001
        configs.append(config)
        return SimpleNamespace(
            text='{"ok": true}',
            usage_metadata=None,
            candidates=[SimpleNamespace(finish_reason=finish_reason)],
        )

    adapter = llm_mod.GeminiCoachLLM.__new__(llm_mod.GeminiCoachLLM)
    adapter._types = SimpleNamespace(
        GenerateContentConfig=lambda **kw: SimpleNamespace(**kw),
        ThinkingConfig=lambda **kw: SimpleNamespace(**kw),
    )
    adapter._client = SimpleNamespace(models=SimpleNamespace(generate_content=generate_content))
    adapter._model = "test-model"
    adapter._api_key = "unused"
    return adapter, configs


def test_gemini_adapter_sends_max_output_tokens(ceiling):
    adapter, configs = _gemini()

    adapter.generate("sys", "user")
    adapter.generate("sys", "user", json_mode=True, thinking_budget=128, max_output_tokens=1024)

    assert configs[0].max_output_tokens == 4096
    assert configs[1].max_output_tokens == 1024
    assert configs[1].response_mime_type == "application/json"


def test_gemini_adapter_omits_the_cap_when_off(ceiling, monkeypatch):
    monkeypatch.setattr(ceiling, "llm_max_output_tokens", 0)
    adapter, configs = _gemini()
    adapter.generate("sys", "user", max_output_tokens=1024)
    assert not hasattr(configs[0], "max_output_tokens")


def test_gemini_adapter_flags_a_max_tokens_cut(ceiling):
    cut, _ = _gemini(finish_reason=SimpleNamespace(name="MAX_TOKENS"))
    whole, _ = _gemini(finish_reason=SimpleNamespace(name="STOP"))
    assert cut.generate("sys", "user").truncated is True
    assert whole.generate("sys", "user").truncated is False


# ---------- 호출처: 잘린 JSON 은 폴백 ----------


#: 계약을 만족하는 루틴 후보. 잘렸다는 표시만 다르게 준다.
_ROUTINE_JSON = """
{"plan_a": {"key": "A", "label": "관절 회복형", "total_minutes": 20, "intensity": "낮음",
  "exercises": [{"name": "저강도 걷기", "minutes": 20, "type": "유산소"}],
  "reason": "부담을 낮춘 구성", "rationale": "최근 기록과 메모를 반영"},
 "plan_b": {"key": "B", "label": "근력 강화형", "total_minutes": 30, "intensity": "보통",
  "exercises": [{"name": "스쿼트", "minutes": 15, "type": "근력"},
                {"name": "실내 자전거", "minutes": 15, "type": "유산소"}],
  "reason": "운동량을 높인 구성", "rationale": "목표와 완료율을 반영"}}
"""


class _Recording:
    """받은 인자를 남기고 정해 둔 결과를 돌려준다."""

    def __init__(self, text: str, *, truncated: bool = False) -> None:
        self._result = LLMResult(text=text, model="stub", truncated=truncated)
        self.kwargs: list[dict] = []

    def generate(self, system_prompt, user_prompt, **kwargs):
        self.kwargs.append(kwargs)
        return self._result


def _routine_request():
    from app.schemas.trainer_api import RoutineOptionsRequest

    return RoutineOptionsRequest(available_minutes=30)


def _routine_analysis():
    from app.schemas.trainer_api import RoutineOptionAnalysisOut

    return RoutineOptionAnalysisOut(
        goal="체중 감량", sodium_today_mg=2200, sodium_over_target=True,
        avg_completion_rate=65, latest_routine="걷기", note="무릎 부담 낮게",
    )


def test_truncated_routine_json_falls_back_to_rules(ceiling, monkeypatch):
    from app.services import trainer_routine_options_service as svc
    llm = _Recording(_ROUTINE_JSON, truncated=True)
    monkeypatch.setattr(svc, "build_member_analysis", lambda *_: _routine_analysis())
    monkeypatch.setattr(svc, "get_coach_llm", lambda *a, **k: llm)
    before = metrics.snapshot()["counters"].get(
        "routine_options.fallback{reason=contract}", 0
    )

    out = svc.generate_routine_options(object(), "trainer", "member", _routine_request())

    # 앞부분만으로도 파싱되는 응답이지만 잘렸다면 쓰지 않는다.
    assert out.generated_by == "rule"
    after = metrics.snapshot()["counters"]["routine_options.fallback{reason=contract}"]
    assert after == before + 1
    assert llm.kwargs[0]["max_output_tokens"] == svc.LLM_MAX_OUTPUT_TOKENS


def _summary_report():
    from app.schemas.trainer_api import WeeklyReportDayOut, WeeklyReportOut

    return WeeklyReportOut(
        member_id="m", member_name="김민수",
        week_start="2026-08-10", week_end="2026-08-16",
        sessions_booked=1, sessions_done=1,
        completion_avg=87, sodium_over_days=4, sodium_avg=2288,
        calories_week=[1710, 1830, 1560, 1900, 1680, 1067, 0],
        days=[WeeklyReportDayOut(completion=67, exercises=["풀업 3세트"])],
        message="",
    )


def test_truncated_report_summary_falls_back_to_rules(ceiling, monkeypatch):
    import json

    from app.services import trainer_report_summary_service as svc
    from app.services.trainer import reports as trainer_reports_service

    report = _summary_report()
    monkeypatch.setattr(
        trainer_reports_service, "build_weekly_report", lambda *a, **k: report
    )
    evidence = svc._evidence(report, "ko")
    reply = json.dumps({"headline": "좋은 한 주", "points": [evidence[0]]}, ensure_ascii=False)
    llm = _Recording(reply, truncated=True)
    monkeypatch.setattr(svc, "get_coach_llm", lambda *a, **k: llm)

    out = svc.generate_summary(None, "t", "m", None, "ko")

    assert out.generated_by == "rule"
    assert llm.kwargs[0]["max_output_tokens"] == svc.LLM_MAX_OUTPUT_TOKENS


def test_truncated_diet_sentence_is_dropped(ceiling, monkeypatch):
    from app.services import diet_ai_sentence as ai

    llm = _Recording('{"sentence": "저녁 국물을', truncated=True)
    monkeypatch.setattr(ai, "get_coach_llm", lambda *a, **k: llm)
    before = metrics.snapshot()["counters"].get("cap_test.fallback{reason=truncated}", 0)

    out = ai.generate(
        lang="ko", analysis_text="", finding="나트륨이 높아요", records=[], notes=[],
        goal="체중 감량", metric="cap_test",
    )

    assert out is None
    after = metrics.snapshot()["counters"]["cap_test.fallback{reason=truncated}"]
    assert after == before + 1
    assert llm.kwargs[0]["max_output_tokens"] == ai.LLM_MAX_OUTPUT_TOKENS


def test_diet_sentence_falls_back_quietly_at_the_global_cap(ceiling, monkeypatch):
    from app.services import ai_call_quota
    from app.services import diet_ai_sentence as ai

    llm = _Recording('{"sentence": "국물은 반만 드세요."}')
    monkeypatch.setattr(ai, "get_coach_llm", lambda *a, **k: llm)

    def _full(feature, *, trainer_id=None):
        raise ai_call_quota.AiCapacityReached(60)

    monkeypatch.setattr(ai_call_quota, "acquire", _full)
    out = ai.generate(
        lang="ko", analysis_text="", finding="나트륨이 높아요", records=[], notes=[],
        goal="체중 감량", metric="cap_test",
    )

    assert out is None
    assert llm.kwargs == [], "상한에 걸리면 모델을 부르지 않는다"
    # 자리를 돌려줬는지 — 다음 호출이 포화로 떨어지지 않는다.
    assert ai._llm_slots.acquire(blocking=False)
    ai._llm_slots.release()


@pytest.mark.parametrize(
    "module_name",
    [
        "app.services.diet_ai_sentence",
        "app.services.diet_menu_plan",
        "app.services.diet_recommendation_service",
        "app.services.trainer_report_summary_service",
        "app.services.trainer_routine_options_service",
        "app.services.exercise_catalog.name_ai",
    ],
)
def test_call_site_caps_stay_under_the_default_ceiling(module_name):
    """호출처 값이 기본 천장보다 크면 설정이 늘 이겨 값이 뜻을 잃는다."""
    import importlib

    from app.core.config import Settings

    module = importlib.import_module(module_name)
    ceiling = Settings.model_fields["llm_max_output_tokens"].default
    assert 0 < module.LLM_MAX_OUTPUT_TOKENS <= ceiling


def test_recognizer_cap_stays_under_the_default_ceiling():
    from app.core.config import Settings
    from app.services.recognizer.base import RECOGNIZER_MAX_OUTPUT_TOKENS

    ceiling = Settings.model_fields["llm_max_output_tokens"].default
    assert 0 < RECOGNIZER_MAX_OUTPUT_TOKENS <= ceiling


# ---------- 인식기 ----------


def test_gemini_recognizer_rejects_a_cut_reply(ceiling):
    import asyncio

    from app.services.recognizer.gemini import GeminiVisionRecognizer

    configs: list[object] = []

    def generate_content(*, model, contents, config):  # noqa: ARG001
        configs.append(config)
        return SimpleNamespace(
            text='{"foods": [{"name": "바나',
            candidates=[SimpleNamespace(finish_reason=SimpleNamespace(name="MAX_TOKENS"))],
        )

    rec = GeminiVisionRecognizer.__new__(GeminiVisionRecognizer)
    rec._client = SimpleNamespace(models=SimpleNamespace(generate_content=generate_content))
    rec._model = "test-model"

    with pytest.raises(RuntimeError):
        asyncio.run(rec.recognize(b"\xff\xd8\xff", "image/jpeg"))
    assert configs[0].max_output_tokens > 0


def test_litellm_recognizer_sends_max_tokens_and_rejects_a_cut_reply(ceiling):
    import asyncio

    from app.services.recognizer.base import RECOGNIZER_MAX_OUTPUT_TOKENS
    from app.services.recognizer.litellm_vision import LiteLLMVisionRecognizer

    sent: list[dict] = []

    def create(**kwargs):
        sent.append(kwargs)
        return SimpleNamespace(
            choices=[
                SimpleNamespace(
                    message=SimpleNamespace(content='{"foods": [{"name": "바나'),
                    finish_reason="length",
                )
            ]
        )

    rec = LiteLLMVisionRecognizer.__new__(LiteLLMVisionRecognizer)
    rec._client = SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(create=create)))
    rec._model = "test-model"

    with pytest.raises(RuntimeError):
        asyncio.run(rec.recognize(b"\xff\xd8\xff", "image/jpeg"))
    assert sent[0]["max_tokens"] == RECOGNIZER_MAX_OUTPUT_TOKENS
