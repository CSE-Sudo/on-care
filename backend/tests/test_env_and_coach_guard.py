"""ENV 허용값과 코치 LLM 키의 운영 기동 검증(#3145) — DB 불필요.

운영 가드는 모두 `is_prod` 에 걸려 있다. `ENV` 에 오타(`prd`)나 다른 표기(`live`)가
들어가면 운영인데도 가드가 모두 꺼진 채 떠서 약한 JWT·데모 폴백까지 켜질 수 있었다.
또 코치 LLM 은 첫 호출 때 만들어져 키가 없어도 서버가 정상 기동했다.
"""
from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.core.config import ENV_VALUES, Settings

_PROD = dict(
    _env_file=None,
    env="prod",
    jwt_secret="a-strong-random-secret-value-for-prod-tests",
    cors_allow_origins="https://app.oncare.com",
    seed_demo_data=False,
    auto_create_tables=False,
    # conftest 가 EMBEDDER=hash 를 환경변수로 심으므로 운영 값을 명시한다.
    gemini_api_key="test-gemini-key",
    recognizer="gemini",
    embedder="gemini",
    coach_llm="gemini",
    # 운영 메일 필수 가드(#3131)와 함께 병합돼도 이 파일이 깨지지 않게 둔다.
    smtp_host="smtp.example.com",
    mail_from="On-Care <no-reply@example.com>",
)


def _prod(**kw) -> Settings:
    return Settings(**{**_PROD, **kw})


def _env(value: str) -> Settings:
    return Settings(_env_file=None, env=value)


# ---- ENV 허용값 ----


def test_allowed_values():
    assert ENV_VALUES == ("dev", "staging", "prod")


@pytest.mark.parametrize("value", ["prd", "live", "production1", "test", "local", "", "  "])
def test_unknown_env_refuses_to_start(value):
    with pytest.raises(ValidationError) as excinfo:
        _env(value)
    message = str(excinfo.value)
    assert "ENV" in message
    assert "dev·staging·prod" in message


def test_unknown_env_from_environment_variable_refuses_to_start(monkeypatch):
    monkeypatch.setenv("ENV", "Prd")
    with pytest.raises(ValidationError, match="ENV"):
        Settings(_env_file=None)


@pytest.mark.parametrize("value", ["prod", "PROD", " prod ", "Prod\n", "production", "PRODUCTION"])
def test_prod_spellings_are_recognized_as_prod(value):
    s = _prod(env=value)
    assert s.env == "prod"
    assert s.is_prod is True


@pytest.mark.parametrize("value", ["prod", " PROD ", "production"])
def test_prod_spellings_keep_every_prod_guard_on(value):
    """대소문자·공백이 달라도 운영 가드가 그대로 걸린다."""
    with pytest.raises(ValidationError, match="JWT_SECRET"):
        _prod(env=value, jwt_secret="short")
    with pytest.raises(ValidationError, match="SEED_DEMO_DATA"):
        _prod(env=value, seed_demo_data=True)


def test_prod_spelling_disables_demo_fallback():
    s = _prod(env=" Production ", allow_demo_fallback=True)
    assert s.demo_fallback_enabled is False


@pytest.mark.parametrize(
    ("value", "expected"),
    [("dev", "dev"), (" DEV ", "dev"), ("staging", "staging"), ("Staging", "staging")],
)
def test_non_prod_values_are_normalized(value, expected):
    s = _env(value)
    assert s.env == expected
    assert s.is_prod is False


def test_default_is_dev(monkeypatch):
    monkeypatch.delenv("ENV", raising=False)
    assert Settings(_env_file=None).env == "dev"


# ---- 코치 LLM 키 ----


def test_prod_boots_with_the_gemini_coach_key():
    s = _prod()
    assert s.coach_llm_problem() is None
    assert s.missing_ai_config() == []


@pytest.mark.parametrize(
    ("overrides", "needle"),
    [
        (
            # 임베딩은 OpenAI 로 채우고 Gemini 키만 비운다 — 인식기와 함께 코치도 보고된다.
            {
                "gemini_api_key": "",
                "embedder": "openai",
                "openai_api_key": "sk-test",
                "coach_llm": "gemini",
            },
            "COACH_LLM=gemini 인데 GEMINI_API_KEY",
        ),
        ({"coach_llm": "openai", "openai_api_key": ""}, "COACH_LLM=openai 인데 OPENAI_API_KEY"),
        ({"coach_llm": "litellm"}, "COACH_LLM=litellm"),
        (
            {
                "coach_llm": "litellm",
                "litellm_base_url": "https://proxy.example",
                "litellm_api_key": "",
            },
            "LITELLM_API_KEY",
        ),
        (
            {
                "coach_llm": "litellm",
                "litellm_base_url": "",
                "litellm_api_key": "vk",
            },
            "LITELLM_BASE_URL",
        ),
        ({"coach_llm": "gpt"}, "COACH_LLM=gpt 는 알 수 없는 코치 LLM"),
        ({"coach_llm": "stub"}, "알 수 없는 코치 LLM"),
    ],
)
def test_prod_refuses_to_start_without_a_usable_coach_llm(overrides, needle):
    with pytest.raises(ValidationError) as excinfo:
        _prod(**overrides)
    message = str(excinfo.value)
    assert needle in message
    assert "코치 LLM" in message


def test_prod_accepts_openai_coach_with_its_key():
    s = _prod(coach_llm="openai", openai_api_key="sk-test")
    assert s.coach_llm_problem() is None


def test_prod_accepts_litellm_coach_when_fully_configured():
    s = _prod(
        coach_llm="litellm",
        litellm_base_url="https://proxy.example",
        litellm_api_key="vk",
    )
    assert s.coach_llm_problem() is None


def test_coach_engine_name_is_case_insensitive():
    s = _prod(coach_llm=" Gemini ")
    assert s.coach_llm_problem() is None


@pytest.mark.parametrize("env", ["dev", "staging"])
def test_non_prod_boots_without_coach_key(env):
    """개발·스테이징은 지금처럼 키 없이 뜬다 — 문제는 알고 있지만 막지 않는다."""
    s = Settings(_env_file=None, env=env, gemini_api_key="", coach_llm="gemini")
    assert s.is_prod is False
    assert s.coach_llm_problem() is not None


def test_coach_problem_matches_what_the_coach_factory_requires():
    """설정 가드가 통과시킨 엔진은 코치 레지스트리에 실제로 있는 이름이다."""
    from app.services.coach.llm import _registry

    for name in _registry():
        s = _prod(
            coach_llm=name,
            openai_api_key="sk-test",
            litellm_base_url="https://proxy.example",
            litellm_api_key="vk",
        )
        assert s.coach_llm_problem() is None, name
