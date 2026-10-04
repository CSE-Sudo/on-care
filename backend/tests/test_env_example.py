"""`.env.example` 이 설정(Settings)과 어긋나지 않는지 — DB 불필요.

새 설정 키를 `config.py` 에 넣고 예시 파일을 빠뜨리면, 배포 담당은 그 키가 있다는 사실
자체를 모른 채 기본값으로 운영하게 된다(#2840). 여기서 둘을 키 단위로 맞춘다.
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.core.config import DEFAULT_DEMO_PASSWORD, DEFAULT_JWT_SECRET, Settings

ENV_EXAMPLE = Path(__file__).resolve().parents[1] / ".env.example"

# 활성 줄(`KEY=값`)과 "기본값을 쓰는 선택 키"로 주석 처리한 줄(`# KEY=값`)을 모두 키로 본다.
# 설명 주석(`#   예: APPLE_CLIENT_IDS=…`)은 `#` 뒤 공백이 하나를 넘어 걸리지 않는다.
_ACTIVE = re.compile(r"^([A-Z][A-Z0-9_]*)=(.*)$")
_OPTIONAL = re.compile(r"^# ([A-Z][A-Z0-9_]*)=(.*)$")

# Settings 필드지만 예시 파일에 일부러 두지 않는 키 — 사유와 함께 적는다.
_INTENTIONALLY_UNDOCUMENTED: dict[str, str] = {}

# Settings 필드가 아니지만 예시 파일에 두는 키 — 사유와 함께 적는다.
_NON_SETTINGS_KEYS: dict[str, str] = {
    "TZ": "프로세스 시간대(로그 타임스탬프). Settings 가 아니라 컨테이너 환경이 읽는다.",
    "FORWARDED_ALLOW_IPS": "uvicorn --forwarded-allow-ips. Settings 가 아니라 scripts/start.sh 가 읽는다.",
    "WEB_CONCURRENCY": "uvicorn 워커 수. Settings 가 아니라 scripts/start.sh 가 읽는다.",
    "MIGRATE_LOCK_TIMEOUT": "기동 마이그레이션 잠금 대기. scripts/migrate.py 가 읽는다.",
    "MIGRATE_LOCK_RETRY_INTERVAL": "기동 마이그레이션 잠금 재시도 간격. scripts/migrate.py 가 읽는다.",
    "MIGRATE_CONNECT_TIMEOUT": "기동 마이그레이션 DB 연결 한도. scripts/migrate.py 가 읽는다.",
}


def _parse() -> tuple[dict[str, str], dict[str, str]]:
    active: dict[str, str] = {}
    optional: dict[str, str] = {}
    for raw in ENV_EXAMPLE.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        if m := _ACTIVE.match(line):
            active[m.group(1)] = m.group(2)
        elif m := _OPTIONAL.match(line):
            optional[m.group(1)] = m.group(2)
    return active, optional


def _settings_keys() -> set[str]:
    return {name.upper() for name in Settings.model_fields}


def test_every_setting_is_in_env_example():
    """config.py 의 모든 설정 키가 예시 파일에 있다(활성 또는 주석 처리된 선택 키)."""
    active, optional = _parse()
    documented = set(active) | set(optional)
    missing = _settings_keys() - documented - set(_INTENTIONALLY_UNDOCUMENTED)
    assert not missing, (
        f".env.example 에 없는 설정 키: {sorted(missing)} — "
        "기본값·운영 권장값 주석과 함께 추가하세요."
    )


def test_env_example_has_no_unknown_keys():
    """예시 파일에 Settings 에 없는(오타·폐기된) 키가 남지 않는다."""
    active, optional = _parse()
    unknown = (set(active) | set(optional)) - _settings_keys() - set(_NON_SETTINGS_KEYS)
    assert not unknown, f"Settings 에 없는 키: {sorted(unknown)}"


def test_env_example_keys_are_not_duplicated():
    """같은 키를 두 번 적으면 뒤의 값이 조용히 이긴다 — 한 번만 둔다."""
    keys: list[str] = []
    for raw in ENV_EXAMPLE.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        if m := _ACTIVE.match(line) or _OPTIONAL.match(line):
            keys.append(m.group(1))
    dupes = sorted({k for k in keys if keys.count(k) > 1})
    assert not dupes, f"중복 키: {dupes}"


def test_allowlists_point_at_real_keys():
    """예외 목록이 낡지 않았다 — 지운 설정이 예외 목록에만 남아 있지 않다."""
    assert set(_INTENTIONALLY_UNDOCUMENTED) <= _settings_keys()
    assert not set(_NON_SETTINGS_KEYS) & _settings_keys()


def test_env_example_has_no_real_looking_secrets():
    """예시 파일에 실제 값처럼 보이는 비밀번호·시크릿이 없다."""
    text = ENV_EXAMPLE.read_text(encoding="utf-8")
    active, _ = _parse()
    # 데모 로그인 비밀번호는 실제 값 대신 주석 처리된 빈 자리표시자로만 둔다.
    assert DEFAULT_DEMO_PASSWORD not in text
    assert active.get("DEMO_LOGIN_PASSWORD", "") == ""
    # 코드의 개발 기본 시크릿을 그대로 베끼지 않는다(교체해야 하는 자리표시자만).
    assert DEFAULT_JWT_SECRET not in text
    assert active["JWT_SECRET"].startswith("CHANGE_ME")
    # 키 값은 전부 비어 있다.
    for key in ("GEMINI_API_KEY", "OPENAI_API_KEY", "KAKAO_REST_API_KEY"):
        assert active.get(key, "") == "", key


def _settings_from_example(**overrides: object) -> Settings:
    active, _ = _parse()
    values: dict[str, object] = {
        k.lower(): v for k, v in active.items() if k.upper() in _settings_keys()
    }
    values.update(overrides)
    return Settings(_env_file=None, **values)


def test_env_example_loads_as_dev_settings():
    """예시를 그대로 복사한 .env 로 개발 서버가 뜬다."""
    s = _settings_from_example()
    assert s.is_prod is False
    assert s.auto_create_tables is True


def test_dev_example_copied_to_prod_is_blocked():
    """개발 예시를 ENV=prod 로만 바꿔 옮기면 운영 가드가 기동을 막는다."""
    with pytest.raises(ValidationError):
        _settings_from_example(env="prod", jwt_secret="a-strong-random-secret-value-for-prod-tests")


def test_prod_recommended_values_pass_guard():
    """예시 주석의 운영 권장값으로 바꾸면 운영 가드를 통과한다."""
    s = _settings_from_example(
        env="prod",
        jwt_secret="a-strong-random-secret-value-for-prod-tests",
        auto_create_tables=False,
        cors_allow_origins="https://app.example.com",
        seed_demo_data=False,
        allow_demo_fallback=False,
        seed_rag_ingest=False,
        force_https=True,
        # 운영은 사진 인식·임베딩 키가 필수다(#2812). 예시 파일은 비워 둔다.
        gemini_api_key="test-gemini-key",
    )
    assert s.is_prod is True
    assert s.demo_fallback_enabled is False
    assert s.force_https is True


@pytest.mark.parametrize(
    "key", ["AI_GLOBAL_CALLS_PER_DAY", "TRAINER_AI_CALLS_PER_DAY", "LLM_MAX_OUTPUT_TOKENS"]
)
def test_ai_cost_caps_are_in_both_examples(key):
    """하루 AI 상한·출력 토큰 상한(#3032)은 개발·배포 예시 둘 다에 값과 함께 있다.

    배포 예시에 빈 값으로 두면 정수 설정이라 기동이 실패한다 — 숫자를 둔다.
    """
    active, _ = _parse()
    assert active.get(key, "").isdigit(), key

    aws = ENV_EXAMPLE.with_name(".env.aws.example").read_text(encoding="utf-8")
    values = [m.group(2) for line in aws.splitlines() if (m := _ACTIVE.match(line.rstrip()))
              and m.group(1) == key]
    assert values and values[0].isdigit(), key


def test_deploy_example_requires_a_paid_gemini_key():
    """운영 키 줄 바로 위에 유료 등급 요구가 적혀 있다(#3032)."""
    aws = ENV_EXAMPLE.with_name(".env.aws.example").read_text(encoding="utf-8")
    before_key = aws.split("\nGEMINI_API_KEY=", 1)[0]
    assert "유료 등급" in before_key.rsplit("\n\n", 1)[-1]
