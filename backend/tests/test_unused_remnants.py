"""쓰지 않는 인식기·설정·배포 문구 정리(#3162) — DB 불필요.

- 실험용 YOLO 인식기 자리는 `NotImplementedError` 만 던졌다. 지정하면 첫 사진 분석이
  실패하므로 등록에서 뺐다.
- LiteLLM 비전 인식기의 엔진 키는 프록시 이름(`litellm`)이다. 코치 LLM·임베딩의
  `litellm` 과 같은 이름이라 설정 하나로 셋을 맞춘다.
- `ADMIN_EMAILS` 는 아무 일도 하지 않아(#3037) 설정·템플릿 파라미터를 지웠다.
"""
from __future__ import annotations

import importlib
from pathlib import Path

import pytest

from app.core.config import Settings
from app.services.recognizer import factory

BACKEND_DIR = Path(__file__).resolve().parents[1]
TEMPLATE = BACKEND_DIR.parent / "infra" / "backend-service.yml"


# ---- 인식기 등록 ----


def test_registered_engines():
    # conftest 가 테스트용 인식기를 하나 더 끼워 넣으므로 포함 관계로 본다.
    registry = set(factory._registry())
    assert {"gemini", "litellm", factory.STUB_ENGINE} <= registry
    assert "yolo" not in registry


def test_yolo_module_is_gone():
    with pytest.raises(ModuleNotFoundError):
        importlib.import_module("app.services.recognizer.yolo")


def test_unknown_engine_names_the_available_ones():
    factory._build.cache_clear()
    with pytest.raises(ValueError) as excinfo:
        factory._build("yolo")
    message = str(excinfo.value)
    assert "litellm" in message
    assert "yolo" not in message.split("사용 가능")[1]


def test_litellm_engine_name_matches_its_registry_key():
    """저장되는 `engine` 값이 설정 키와 같다 — 기록을 보고 어느 설정이었는지 안다."""
    from app.services.recognizer.litellm_vision import LiteLLMVisionRecognizer

    assert factory._registry()["litellm"] is LiteLLMVisionRecognizer
    assert LiteLLMVisionRecognizer.name == "litellm"


def test_prod_accepts_the_litellm_recognizer_key():
    s = Settings(
        _env_file=None,
        recognizer="litellm",
        litellm_base_url="https://proxy.example",
        litellm_api_key="vk",
    )
    assert s.recognizer_problem() is None


def test_prod_problem_lists_the_supported_recognizers():
    problem = Settings(_env_file=None, recognizer="yolo").recognizer_problem()
    assert problem is not None
    assert "gemini|litellm" in problem


# ---- ADMIN_EMAILS ----


def test_service_template_has_no_admin_emails():
    text = TEMPLATE.read_text(encoding="utf-8")
    assert "AdminEmails" not in text
    assert "ADMIN_EMAILS" not in text


@pytest.mark.parametrize("name", [".env.example", ".env.aws.example"])
def test_env_examples_have_no_admin_emails_key(name):
    lines = (BACKEND_DIR / name).read_text(encoding="utf-8").splitlines()
    assert not any(line.startswith("ADMIN_EMAILS=") for line in lines)


# ---- 배포 구조 문구 ----


def test_liveness_docstring_matches_the_current_platform():
    from app.api.v1 import system

    doc = system.healthz.__doc__ or ""
    assert "App Runner" not in doc
