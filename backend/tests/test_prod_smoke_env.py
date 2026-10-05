"""운영 설정 기동 스모크의 더미 값이 운영 가드를 통과하는지 확인한다(#3163) — DB 불필요.

백엔드 CI 의 이미지 잡은 `tests/fixtures/prod_smoke.env` 로 컨테이너를 ENV=prod 로 띄우고
(`.github/scripts/backend_prod_boot_smoke.sh`), 필수 값을 하나씩 빼면 기동이 멈추는지 본다.
컨테이너 스모크는 실패 원인을 로그로만 알려 주므로, 같은 값을 여기서 설정 가드
(`Settings._guard_prod_secrets`)와 기동 점검(`startup_checks.check`)에 직접 넣어 본다.
운영 가드가 새로 생기면 이 테스트가 먼저 실패해 더미 값을 함께 더하라고 알려 준다.
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

from app.core import startup_checks
from app.core.config import Settings

BACKEND = Path(__file__).resolve().parents[1]
ENV_FILE = BACKEND / "tests" / "fixtures" / "prod_smoke.env"
SMOKE_SCRIPT = BACKEND.parent / ".github" / "scripts" / "backend_prod_boot_smoke.sh"


def read_env_file(path: Path) -> dict[str, str]:
    """`docker run --env-file` 과 같은 규칙: 빈 줄·`#` 로 시작하는 줄은 건너뛰고 첫 `=` 에서 나눈다."""
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        key, sep, value = line.partition("=")
        assert sep, f"{path.name}: '=' 가 없는 줄: {line!r}"
        assert key == key.strip() and key, f"{path.name}: 키 앞뒤 공백: {line!r}"
        assert key not in values, f"{path.name}: {key} 가 두 번 있다"
        values[key] = value
    return values


def required_cases() -> list[tuple[str, str]]:
    """스모크 스크립트의 REQUIRED_CASES — (뺄 키, 로그에 나와야 할 문구)."""
    text = SMOKE_SCRIPT.read_text(encoding="utf-8")
    block = re.search(r"^REQUIRED_CASES=\(\n(?P<body>.*?)^\)", text, re.MULTILINE | re.DOTALL)
    assert block, "backend_prod_boot_smoke.sh 에 REQUIRED_CASES 가 없다"
    cases = re.findall(r'^\s*"([A-Z0-9_]+)\|([^"]+)"\s*$', block.group("body"), re.MULTILINE)
    assert cases, "REQUIRED_CASES 가 비어 있다"
    return cases


ENV_VALUES = read_env_file(ENV_FILE)


@pytest.fixture
def prod_env(monkeypatch):
    """CI 잡의 env(ENV=dev 등)를 지우고 더미 운영 값만 남긴다."""
    for key in list(Settings.model_fields):
        monkeypatch.delenv(key.upper(), raising=False)
    for key, value in ENV_VALUES.items():
        monkeypatch.setenv(key, value)
    return monkeypatch


def _boot(**overrides) -> Settings:
    """컨테이너 기동 순서대로 — 설정 로드(가드) → 기동 점검."""
    settings = Settings(_env_file=None, **overrides)
    startup_checks.check(settings)
    return settings


def test_env_file_boots_as_production(prod_env):
    s = _boot()
    assert s.is_prod
    assert s.force_https
    assert not s.api_docs_enabled
    assert not s.demo_fallback_enabled
    assert s.mail_backend == "smtp" and s.mail_enabled
    assert s.missing_ai_config() == []
    assert s.cors_prod_problem() is None


def test_env_file_uses_a_direct_database_url():
    url = ENV_VALUES["DATABASE_URL"]
    assert url.startswith("postgresql+psycopg://")
    assert "localhost:5432" in url
    assert "-pooler" not in url


def test_env_file_holds_only_dummy_secrets():
    for key in ("JWT_SECRET", "GEMINI_API_KEY", "SMTP_PASSWORD", "SMTP_USERNAME", "ATTACHMENT_S3_BUCKET"):
        assert "dummy" in ENV_VALUES[key], f"{key} 는 더미 값임이 이름에 드러나야 한다"
    assert len(ENV_VALUES["JWT_SECRET"].encode()) >= 32


def test_env_file_keys_are_known_settings():
    # 오타 난 키는 조용히 무시돼 스모크가 엉뚱한 기본값으로 돈다.
    known = {name.upper() for name in Settings.model_fields}
    entrypoint_only = {"TZ", "WEB_CONCURRENCY", "PORT", "FORWARDED_ALLOW_IPS"}
    unknown = set(ENV_VALUES) - known - entrypoint_only
    assert not unknown, f"Settings 에 없는 키: {sorted(unknown)}"


def test_env_file_matches_the_production_template_switches():
    # 운영 템플릿이 고정하는 스위치와 같은 값으로 띄운다.
    template = (BACKEND.parent / "infra" / "backend-service.yml").read_text(encoding="utf-8")
    for key in ("AUTO_CREATE_TABLES", "FORCE_HTTPS", "ATTACHMENT_STORAGE", "RECOGNIZER", "EMBEDDER", "COACH_LLM"):
        match = re.search(rf"- Name: {key}\n\s+Value: '?([A-Za-z0-9_-]+)'?", template)
        assert match, f"infra/backend-service.yml 에 {key} 가 없다"
        assert ENV_VALUES[key] == match.group(1), key


@pytest.mark.parametrize(("key", "needle"), required_cases())
def test_removing_a_required_value_blocks_boot(prod_env, key, needle):
    assert key in ENV_VALUES, f"prod_smoke.env 에 {key} 가 없다"
    prod_env.delenv(key)
    with pytest.raises((ValueError, startup_checks.StartupConfigError)) as caught:
        _boot()
    assert needle in str(caught.value)


def test_smoke_cases_cover_the_main_guards():
    keys = {key for key, _ in required_cases()}
    main_guards = {
        "JWT_SECRET",
        "CORS_ALLOW_ORIGINS",
        "GEMINI_API_KEY",
        "ATTACHMENT_S3_BUCKET",
    }
    assert main_guards <= keys
