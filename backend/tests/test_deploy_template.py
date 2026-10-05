"""ECS 서비스 템플릿(infra/backend-service.yml)이 설정(Settings)과 어긋나지 않는지 — DB 불필요.

배포 설정의 원본은 템플릿이다(#3016). 템플릿에 오타 난 키를 넣으면 앱은 조용히 기본값으로
뜨고, 새 설정 키를 `.env.aws.example` 에만 적으면 운영에는 들어가지 않는다. 여기서 셋
(Settings · 템플릿 · 운영 예시 파일)을 키 단위로 맞추고, 템플릿의 운영 값이 운영 가드를
통과하는지 본다.
"""
from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import yaml

from app.core.config import Settings

BACKEND_DIR = Path(__file__).resolve().parents[1]
TEMPLATE = BACKEND_DIR.parent / "infra" / "backend-service.yml"
AWS_EXAMPLE = BACKEND_DIR / ".env.aws.example"

# Settings 필드가 아니지만 컨테이너에 넣는 키 — 사유와 함께 적는다.
_NON_SETTINGS_KEYS: dict[str, str] = {
    "TZ": "프로세스 시간대(로그 타임스탬프). 컨테이너 환경이 읽는다.",
    "WEB_CONCURRENCY": "uvicorn 워커 수. Settings 가 아니라 scripts/start.sh 가 읽는다.",
    "MIGRATE_LOCK_TIMEOUT": "기동 마이그레이션 lock 대기 한도. Settings 가 아니라 scripts/migrate.py 가 읽는다.",
    "MIGRATE_CONNECT_TIMEOUT": "기동 마이그레이션 DB 연결 한도. Settings 가 아니라 scripts/migrate.py 가 읽는다.",
    "MIGRATE_LOCK_RETRY_INTERVAL": "기동 마이그레이션 lock 재시도 간격. Settings 가 아니라 scripts/migrate.py 가 읽는다.",
}

# 템플릿에는 있지만 운영 예시 파일에 두지 않는 키.
_STAGING_ONLY = {"DEMO_LOGIN_PASSWORD"}


class _CfnLoader(yaml.SafeLoader):
    """`!Ref`·`!Sub` 같은 CloudFormation 태그를 `{"!Tag": 값}` 으로 읽는다."""


def _construct_tag(loader: yaml.SafeLoader, suffix: str, node: yaml.Node) -> dict[str, Any]:
    if isinstance(node, yaml.ScalarNode):
        value: Any = loader.construct_scalar(node)
    elif isinstance(node, yaml.SequenceNode):
        value = loader.construct_sequence(node, deep=True)
    else:
        value = loader.construct_mapping(node, deep=True)
    return {f"!{suffix}": value}


_CfnLoader.add_multi_constructor("!", _construct_tag)


def _template() -> dict[str, Any]:
    with TEMPLATE.open(encoding="utf-8") as handle:
        return yaml.load(handle, Loader=_CfnLoader)  # noqa: S506 — SafeLoader 파생


def _entries(kind: str) -> list[dict[str, Any]]:
    """컨테이너 Environment/Secrets 항목. 조건부(`!If`) 항목은 참일 때 값을 꺼낸다."""
    container = _template()["Resources"]["BackendService"]["Properties"]["PrimaryContainer"]
    found: list[dict[str, Any]] = []
    for item in container[kind]:
        if "!If" in item:
            item = item["!If"][1]
        found.append(item)
    return found


def _template_keys() -> set[str]:
    return {item["Name"] for item in _entries("Environment") + _entries("Secrets")}


def _settings_keys() -> set[str]:
    return {name.upper() for name in Settings.model_fields}


def _aws_example_keys() -> set[str]:
    pattern = re.compile(r"^([A-Z][A-Z0-9_]*)=")
    return {
        m.group(1)
        for raw in AWS_EXAMPLE.read_text(encoding="utf-8").splitlines()
        if (m := pattern.match(raw.strip()))
    }


def test_template_keys_are_settings():
    """템플릿의 환경변수·비밀 이름이 전부 Settings 키다(오타가 기본값으로 숨지 않게)."""
    unknown = _template_keys() - _settings_keys() - set(_NON_SETTINGS_KEYS)
    assert not unknown, f"Settings 에 없는 키: {sorted(unknown)}"


def test_non_settings_allowlist_is_not_stale():
    assert not set(_NON_SETTINGS_KEYS) & _settings_keys()
    assert set(_NON_SETTINGS_KEYS) <= _template_keys()


def test_template_keys_are_not_duplicated():
    names = [item["Name"] for item in _entries("Environment") + _entries("Secrets")]
    dupes = sorted({n for n in names if names.count(n) > 1})
    assert not dupes, f"중복 키: {dupes}"


def test_aws_example_matches_template():
    """운영 예시 파일과 템플릿이 같은 키를 다룬다 — 한쪽에만 적은 설정은 운영에 안 들어간다."""
    template = _template_keys() - _STAGING_ONLY
    example = _aws_example_keys()
    assert example - template == set(), f"템플릿에 없는 예시 키: {sorted(example - template)}"
    assert template - example == set(), f"예시 파일에 없는 템플릿 키: {sorted(template - example)}"


def test_sensitive_values_come_from_secrets():
    """민감값은 평문 환경변수가 아니라 Secrets Manager 참조로만 들어간다."""
    secrets = {item["Name"] for item in _entries("Secrets")}
    plain = {item["Name"] for item in _entries("Environment")}
    sensitive = {"DATABASE_URL", "JWT_SECRET", "GEMINI_API_KEY", "KAKAO_REST_API_KEY", "SENTRY_DSN"}
    assert sensitive <= secrets
    assert not sensitive & plain


# 스택 파라미터가 비면 아예 넣지 않는 키(!If). 운영 가드 검사에서는 빈 값과 같다.
_OPTIONAL_PARAMETER_KEYS = {"GOOGLE_CLIENT_IDS", "KAKAO_APP_ID"}


def _production_values() -> dict[str, object]:
    """템플릿의 운영 값. 파라미터·비밀 자리는 형식에 맞는 시험 값으로 채운다."""
    mapping = _template()["Mappings"]["EnvironmentSettings"]["production"]
    placeholders: dict[str, object] = {
        "CORS_ALLOW_ORIGINS": "https://app.example.com,https://trainer.example.com",
        "GEMINI_MODEL": "gemini-test-flash",
        "ATTACHMENT_S3_BUCKET": "oncare-attachments-test",
        "ATTACHMENT_S3_REGION": "ap-southeast-1",
        "DATABASE_URL": "postgresql+psycopg://user:pass@db.example.com/oncare",
        "JWT_SECRET": "a-strong-random-secret-value-for-prod-tests",
        "GEMINI_API_KEY": "test-gemini-key",
        "KAKAO_REST_API_KEY": "",
        "SENTRY_DSN": "",
        "MAIL_FROM": "noreply@example.com",
        "SMTP_HOST": "smtp.example.com",
        "SMTP_PORT": "587",
        "SMTP_USERNAME": "smtp-user",
        "SMTP_PASSWORD": "smtp-password",
        "PASSWORD_RESET_MEMBER_URL": "https://app.example.com/reset",
        "PASSWORD_RESET_TRAINER_URL": "https://trainer.example.com/reset",
    }
    values: dict[str, object] = {}
    for item in _entries("Environment"):
        name, value = item["Name"], item["Value"]
        if name in _NON_SETTINGS_KEYS or name in _OPTIONAL_PARAMETER_KEYS:
            continue
        if isinstance(value, dict) and "!FindInMap" in value:
            value = mapping[value["!FindInMap"][2]]
        elif isinstance(value, dict) and "!If" in value:
            value = value["!If"][2]  # 운영(IsStaging=false) 쪽 값
        elif isinstance(value, dict):
            value = placeholders[name]
        values[name.lower()] = value
    for item in _entries("Secrets"):
        if item["Name"] in _STAGING_ONLY:
            continue
        values[item["Name"].lower()] = placeholders[item["Name"]]
    return values


def test_production_template_passes_prod_guard():
    """템플릿 운영 값 그대로 운영 가드를 통과하고, 데모 경로가 꺼진다."""
    s = Settings(_env_file=None, **_production_values())
    assert s.is_prod is True
    assert s.demo_fallback_enabled is False
    assert s.seed_demo_data is False
    assert s.auto_create_tables is False
    assert s.force_https is True
    assert s.trusted_proxy_hops == 1
    assert s.attachment_storage == "s3"


def test_mail_template_values_enable_smtp():
    """메일 파라미터를 채운 운영 값이면 SMTP 발송이 켜진다(비밀번호 재설정, #2824)."""
    s = Settings(_env_file=None, **_production_values())
    assert s.mail_provider == "smtp"
    assert s.smtp_port == 587
