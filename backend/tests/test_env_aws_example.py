"""운영 환경변수 템플릿 `.env.aws.example` 이 설정과 어긋나지 않는지 — DB 불필요. (#3034)

배포 담당은 이 템플릿으로 App Runner 환경변수를 채우고, 운영 체크리스트 첫 항목도
"템플릿의 키를 모두 갖는다" 다. 새 설정 키를 `config.py` 에 넣고 템플릿을 빠뜨리면 그 키는
아무도 모르는 채 개발 기본값으로 운영된다. 개발 예시(`.env.example`)는 103개 키를 모두
적지만, 운영 템플릿은 읽을 수 있는 길이로 두려고 **기본값이 곧 운영값인 키는 일부러 뺀다.**
여기서는 "빠진 것" 과 "일부러 뺀 것" 을 사유와 함께 가른다.
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

from app.core.config import Settings

BACKEND = Path(__file__).resolve().parents[1]
AWS_EXAMPLE = BACKEND / ".env.aws.example"
DEV_EXAMPLE = BACKEND / ".env.example"
START_SCRIPT = BACKEND / "scripts" / "start.sh"
MIGRATE_SCRIPT = BACKEND / "scripts" / "migrate.py"

# `.env.example` 과 같은 규약 — 활성 줄 `KEY=값`, 기본값을 쓰는 선택 키 `# KEY=값`.
_ACTIVE = re.compile(r"^([A-Z][A-Z0-9_]*)=(.*)$")
_OPTIONAL = re.compile(r"^# ([A-Z][A-Z0-9_]*)=(.*)$")

_RATE_LIMIT = "시도 제한 값 — 기본값이 운영값이다. 바꿀 때는 .env.example 의 설명을 본다."
_OTHER_AI = "다른 AI 공급자 — 운영 기본값·이 템플릿은 Gemini 다. 바꾸면 처리방침 수탁자도 고친다."
_RAG_TUNING = "RAG 조정값 — 기본값이 운영값이다."
_UPLOAD = "업로드 상한 — 기본값이 운영값이다."
_LOCAL_DIR = "로컬 저장 경로 — 운영 첨부는 S3(ATTACHMENT_*)라 쓰지 않는다."

# Settings 필드지만 운영 템플릿에 일부러 두지 않는 키 — 사유와 함께 적는다.
_AWS_INTENTIONALLY_OMITTED: dict[str, str] = {
    "API_V1_PREFIX": "두 앱이 /v1 을 가정한다. 운영에서 바꾸지 않는다.",
    "APP_VERSION": "코드가 정하는 버전 문자열. 환경변수로 덮지 않는다.",
    "MIN_MEMBER_APP_VERSION": "회원 앱 최소 지원 버전 — 비어 있으면(기본값) 업데이트를 강제하지 않는다. 강제 업데이트가 필요할 때만 설정한다.",
    "JWT_ALGORITHM": "HS256 고정. 바꾸면 발급된 토큰이 모두 무효가 된다.",
    "AUDIT_READ_DEDUPE_MINUTES": "열람 기록 중복 제거 창 — 기본값이 운영값이다.",
    "NUTRITION_DB_ENRICH": "공공 영양 DB 보강 — 운영은 기본값(true). 비교실험 때만 끈다.",
    "EXERCISE_NAME_AI": "운동 이름 AI 접기 — 운영은 기본값(true).",
    "KAKAO_TIMEOUT_SECONDS": "카카오 호출 대기 — 기본값이 운영값이다.",
    "SESSION_MAX_DAYS": "로그인 한 번의 최대 기간(모바일) — 기본값(90일)이 운영값이다(#3086).",
    "WEB_SESSION_MAX_DAYS": "로그인 한 번의 최대 기간(웹) — 기본값(30일)이 운영값이다(#3086).",
    "REFRESH_REUSE_GRACE_SECONDS": "동시 갱신으로 보는 refresh 재사용 유예 — 기본값(30초)이 운영값이다(#3086).",
    "CHAT_IMAGE_STORAGE_DIR": _LOCAL_DIR,
    "REPORT_PDF_STORAGE_DIR": _LOCAL_DIR,
    "MAX_UPLOAD_BYTES": _UPLOAD,
    "MAX_CHAT_IMAGE_BYTES": _UPLOAD,
    "MAX_REPORT_PDF_BYTES": _UPLOAD,
    "UPLOAD_BODY_SLACK_BYTES": _UPLOAD,
    "MAX_IMAGE_DECODE_PIXELS": _UPLOAD,
    "MAX_IMAGE_DECODE_EDGE": _UPLOAD,
    "CHUNK_WINDOW": _RAG_TUNING,
    "CHUNK_OVERLAP": _RAG_TUNING,
    "RETRIEVE_PUBLIC_K": _RAG_TUNING,
    "RETRIEVE_PERSONAL_K": _RAG_TUNING,
    "RAG_AUTO_INGEST": _RAG_TUNING,
    "SEED_RAG_INGEST": "데모 시드 기록의 개인 문서 적재 — 운영은 데모 시드가 꺼져 있어(SEED_DEMO_DATA=false) 돌지 않는다.",
    "OPENAI_API_KEY": _OTHER_AI,
    "OPENAI_CHAT_MODEL": _OTHER_AI,
    "OPENAI_EMBED_MODEL": _OTHER_AI,
    "LITELLM_BASE_URL": _OTHER_AI,
    "LITELLM_API_KEY": _OTHER_AI,
    "LITELLM_CHAT_MODEL": _OTHER_AI,
    "LITELLM_VISION_MODEL": _OTHER_AI,
    "LITELLM_EMBED_MODEL": _OTHER_AI,
    "RATE_LIMIT_AUTH_PER_MINUTE": _RATE_LIMIT,
    "COACH_CHAT_PER_MINUTE": _RATE_LIMIT,
    "COACH_CHAT_MAX_BODY_BYTES": _RATE_LIMIT,
    "COACH_CHAT_FREE_PER_DAY": _RATE_LIMIT,
    "COACH_CHAT_PAID_COST": _RATE_LIMIT,
    "COACH_CHAT_PAID_PER_DAY": _RATE_LIMIT,
    "ROUTINE_OPTIONS_PER_MINUTE": _RATE_LIMIT,
    "DIET_ANALYZE_PER_MINUTE": _RATE_LIMIT,
    "DIET_ANALYZE_PER_DAY": _RATE_LIMIT,
    "CONSULTATION_MAX_PENDING": _RATE_LIMIT,
    "CONSULTATION_CREATE_PER_DAY": _RATE_LIMIT,
    "LOGIN_MAX_FAILURES": _RATE_LIMIT,
    "LOGIN_LOCKOUT_SECONDS": _RATE_LIMIT,
    "PAIRING_REDEEM_PER_DAY": _RATE_LIMIT,
    "REGISTER_PER_EMAIL_PER_HOUR": _RATE_LIMIT,
    "PASSWORD_CHANGE_MAX_FAILURES": _RATE_LIMIT,
}

# 배포 과정이 넣는 키 — 템플릿에 적지 않는다. Settings 필드인지와 무관하게 허용한다.
_AWS_INJECTED: dict[str, str] = {
    "PORT": "App Runner 가 넣는다. scripts/start.sh 가 ${PORT:-8000} 으로 읽는다.",
    "GIT_SHA": "배포 워크플로가 이미지 빌드 인자로 넣는다(#3029).",
}

# Settings 필드가 아니지만 템플릿에 두는 키 — 사유와 함께 적는다.
_AWS_NON_SETTINGS_KEYS: dict[str, str] = {
    "TZ": "프로세스 시간대(로그 타임스탬프). 컨테이너 환경이 읽는다.",
    "FORWARDED_ALLOW_IPS": "uvicorn --forwarded-allow-ips. scripts/start.sh 가 읽는다.",
    "WEB_CONCURRENCY": "uvicorn 워커 수. scripts/start.sh 가 읽는다.",
    "MIGRATE_LOCK_TIMEOUT": "기동 마이그레이션 잠금 대기. scripts/migrate.py 가 읽는다.",
    "MIGRATE_LOCK_RETRY_INTERVAL": "기동 마이그레이션 잠금 재시도 간격. scripts/migrate.py 가 읽는다.",
    "MIGRATE_CONNECT_TIMEOUT": "기동 마이그레이션 DB 연결 한도. scripts/migrate.py 가 읽는다.",
}

# 운영 템플릿의 활성 값이 운영 가드·운영 결정과 같아야 하는 키.
_PROD_VALUES: dict[str, str] = {
    "ENV": "prod",
    "AUTO_CREATE_TABLES": "false",
    "SEED_DEMO_DATA": "false",
    "ALLOW_DEMO_FALLBACK": "false",
    "ATTACHMENT_STORAGE": "s3",
    "FORCE_HTTPS": "true",
    "SECURITY_HEADERS": "true",
    "RATE_LIMIT_ENABLED": "true",
    # 태스크·워커가 여럿이어도 한도가 하나이도록 공유 저장소에 센다(#3143).
    "RATE_LIMIT_STORE": "database",
    "GYM_BENEFITS_ENABLED": "false",
    "EXPOSE_API_DOCS": "false",
    # auto 면 SMTP 를 빠뜨려도 조용히 꺼진다. smtp 로 두면 기동에서 드러난다(#3033).
    "MAIL_PROVIDER": "smtp",
}

# 운영에서 값을 넣어야 하는 메일·재설정 키 — 주석 줄이 아니라 활성 줄로 있어야 한다(#3033).
_MAIL_KEYS = (
    "MAIL_PROVIDER",
    "MAIL_FROM",
    "SMTP_HOST",
    "SMTP_PORT",
    "SMTP_USERNAME",
    "SMTP_PASSWORD",
    "SMTP_STARTTLS",
    "SMTP_SSL",
    "PASSWORD_RESET_MEMBER_URL",
    "PASSWORD_RESET_TRAINER_URL",
)

# 템플릿에 비밀값이 들어가면 안 되는 키 — 모두 비어 있어야 한다.
_SECRET_KEYS = (
    "DATABASE_URL",
    "JWT_SECRET",
    "GEMINI_API_KEY",
    "KAKAO_REST_API_KEY",
    "SMTP_USERNAME",
    "SMTP_PASSWORD",
    "SENTRY_DSN",
)


def _parse(path: Path) -> tuple[dict[str, str], dict[str, str], list[str]]:
    active: dict[str, str] = {}
    optional: dict[str, str] = {}
    order: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        if m := _ACTIVE.match(line):
            active[m.group(1)] = m.group(2)
            order.append(m.group(1))
        elif m := _OPTIONAL.match(line):
            optional[m.group(1)] = m.group(2)
            order.append(m.group(1))
    return active, optional, order


def _documented(path: Path) -> set[str]:
    active, optional, _ = _parse(path)
    return set(active) | set(optional)


def _settings_keys() -> set[str]:
    return {name.upper() for name in Settings.model_fields}


def test_every_setting_is_in_the_template_or_omitted_on_purpose():
    """모든 설정 키가 템플릿에 있거나, 일부러 뺀 목록에 사유와 함께 있다."""
    missing = (
        _settings_keys()
        - _documented(AWS_EXAMPLE)
        - set(_AWS_INTENTIONALLY_OMITTED)
        - set(_AWS_INJECTED)
    )
    assert not missing, (
        f".env.aws.example 에 없는 설정 키: {sorted(missing)} — 운영에서 값을 정해야 하면 "
        "템플릿에, 기본값이 운영값이면 이 파일의 _AWS_INTENTIONALLY_OMITTED 에 사유와 함께 넣으세요."
    )


def test_template_has_no_unknown_keys():
    """템플릿에 Settings 에 없는(오타·폐기된) 키가 남지 않는다."""
    unknown = _documented(AWS_EXAMPLE) - _settings_keys() - set(_AWS_NON_SETTINGS_KEYS)
    assert not unknown, f"Settings 에 없는 키: {sorted(unknown)}"


def test_template_keys_are_not_duplicated():
    _, _, order = _parse(AWS_EXAMPLE)
    dupes = sorted({k for k in order if order.count(k) > 1})
    assert not dupes, f"중복 키: {dupes}"


def test_omitted_keys_are_not_also_in_the_template():
    """일부러 뺐다고 적은 키가 템플릿에 있으면 둘 중 하나가 낡았다."""
    both = (set(_AWS_INTENTIONALLY_OMITTED) | set(_AWS_INJECTED)) & _documented(AWS_EXAMPLE)
    assert not both, f"템플릿에도 있고 제외 목록에도 있는 키: {sorted(both)}"


def test_allowlists_point_at_real_keys():
    """제외 목록이 낡지 않았다 — 지운 설정이 목록에만 남지 않는다."""
    assert set(_AWS_INTENTIONALLY_OMITTED) <= _settings_keys()
    assert not set(_AWS_NON_SETTINGS_KEYS) & _settings_keys()
    for reason in (*_AWS_INTENTIONALLY_OMITTED.values(), *_AWS_INJECTED.values()):
        assert reason.strip()


@pytest.mark.parametrize(("key", "value"), sorted(_PROD_VALUES.items()))
def test_template_carries_prod_values(key, value):
    active, _, _ = _parse(AWS_EXAMPLE)
    assert active.get(key) == value, f"{key} 는 운영 템플릿에서 {value} 여야 한다"


@pytest.mark.parametrize("key", _MAIL_KEYS)
def test_mail_and_reset_keys_are_active_lines(key):
    """메일·재설정 키는 운영에서 채워야 하므로 활성 줄이다(#3033)."""
    active, _, _ = _parse(AWS_EXAMPLE)
    assert key in active, key


def test_reset_url_guidance_is_hash_style():
    """재설정 화면 주소 안내가 두 앱의 실제 배포 형식(해시·하위 경로)이다(#3033)."""
    text = AWS_EXAMPLE.read_text(encoding="utf-8")
    assert "/frontend/#/auth/password-reset" in text
    assert "/trainer/#/auth/password-reset" in text
    dev = DEV_EXAMPLE.read_text(encoding="utf-8")
    assert "/frontend/#/auth/password-reset" in dev
    assert "/trainer/#/auth/password-reset" in dev


@pytest.mark.parametrize("key", _SECRET_KEYS)
def test_template_has_no_secret_values(key):
    active, _, _ = _parse(AWS_EXAMPLE)
    assert active.get(key, "") == "", key


def _script_env_keys() -> set[str]:
    """두 기동 스크립트가 읽는 환경변수(셸 내부 변수·PORT 제외)."""
    shell = set(re.findall(r"\$\{?([A-Z][A-Z0-9_]*)", START_SCRIPT.read_text(encoding="utf-8")))
    shell -= {"ENV_TRIMMED"}
    migrate = MIGRATE_SCRIPT.read_text(encoding="utf-8")
    py = set(re.findall(r"os\.environ\.get\(\s*\"([A-Z][A-Z0-9_]*)\"", migrate))
    py |= set(re.findall(r"os\.environ\[\s*\"([A-Z][A-Z0-9_]*)\"\s*\]", migrate))
    return (shell | py) - set(_AWS_INJECTED)


def test_script_keys_are_in_both_examples():
    """start.sh·migrate.py 가 읽는 키가 두 예시 파일에 모두 있다 — Settings 대조 테스트가 못 잡는다."""
    keys = _script_env_keys()
    assert {"ENV", "WEB_CONCURRENCY", "FORWARDED_ALLOW_IPS", "MIGRATE_LOCK_TIMEOUT"} <= keys
    for path in (AWS_EXAMPLE, DEV_EXAMPLE):
        missing = keys - _documented(path)
        assert not missing, f"{path.name} 에 없는 스크립트 키: {sorted(missing)}"


def test_template_with_secrets_filled_passes_prod_guard():
    """템플릿 값에 비밀값·도메인만 채우면 운영 가드를 통과한다 — 빈 정수 같은 함정이 없다."""
    active, _, _ = _parse(AWS_EXAMPLE)
    settings_keys = _settings_keys()
    values: dict[str, object] = {
        k.lower(): v for k, v in active.items() if k in settings_keys
    }
    values.update(
        database_url="postgresql+psycopg://u:p@db.example/oncare",
        jwt_secret="a-strong-random-secret-value-for-prod-tests",
        cors_allow_origins="https://app.oncare.example,https://trainer.oncare.example",
        gemini_api_key="test-gemini-key",
        attachment_s3_bucket="oncare-prod",
        mail_from="no-reply@oncare.example",
        smtp_host="smtp.oncare.example",
        password_reset_member_url="https://oncare.example/frontend/#/auth/password-reset",
        password_reset_trainer_url="https://oncare.example/trainer/#/auth/password-reset",
    )
    s = Settings(_env_file=None, **values)
    assert s.is_prod is True
    assert s.mail_enabled is True
    assert s.demo_fallback_enabled is False
    assert s.trusted_proxy_hops == 1
